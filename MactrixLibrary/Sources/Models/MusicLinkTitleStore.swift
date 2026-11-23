import Foundation

/// The titles of the Spotify song and album links (MATRIX-191), with a disk
/// cache.
///
/// The timeline's music link marker asks `title(for:)` while it parses a
/// body, so a title the store holds is in the first layout of the row. A
/// body that shows asks `load(_:)` for its links, and the store reads the
/// homeserver's URL preview of each link it has no answer for. When a title
/// arrives, the store changes `titles` (observed, so the shown bodies parse
/// again) and posts `titlesDidChange`, so the timeline measures the rows of
/// that link again.
///
/// Rules:
/// - Only Spotify links have a title. The homeserver previews no other host.
/// - The key of a link is `cacheKey(for:)`: no query, no fragment, no
///   trailing slash, a lowercase scheme and host.
/// - A title lives `titleLifetime` (30 days). A failed read (a Matrix error
///   from the homeserver, no preview, a preview with no title) lives
///   `failureLifetime` (1 hour), and a read with no Matrix answer (no
///   network, `MusicLinkPreviewFailure.isTransient`) lives
///   `transportFailureLifetime`. While a failure lives, `load` makes no read
///   for the link. An expired entry counts as absent.
/// - One read per link at a time: a second `load` while a read is in flight
///   does nothing. At most `maxConcurrentReads` reads run at once, the others
///   wait in order.
/// - The cache file holds the titles and the failures with their expiry
///   dates, at most `capacity` entries. It never holds a token or a response
///   body.
///
/// The store has no network of its own: `configure` gives it the read (the
/// SDK's URL preview call in `Core`) and the cache file, so tests run from
/// fixtures.
@MainActor @Observable
public final class MusicLinkTitleStore {
    /// The store of the app's session. `Core` configures it when the client
    /// starts.
    public static let shared = MusicLinkTitleStore()

    /// Reads the URL preview of a link and returns its JSON body.
    public typealias Fetch = @MainActor (URL) async throws -> Data

    /// Posted on the main thread when titles arrive. `userInfo[changedKeysKey]`
    /// holds the keys (`cacheKey(for:)`) of the new titles.
    public nonisolated static let titlesDidChange = Notification.Name("MactrixMusicLinkTitlesDidChange")
    /// The `userInfo` key of `titlesDidChange`: a `[String]`.
    public nonisolated static let changedKeysKey = "keys"

    public nonisolated static let titleLifetime: TimeInterval = 30 * 24 * 60 * 60
    public nonisolated static let failureLifetime: TimeInterval = 60 * 60
    public nonisolated static let transportFailureLifetime: TimeInterval = 5 * 60
    public nonisolated static let maxConcurrentReads = 4
    public nonisolated static let capacity = 2000

    struct Entry: Codable, Equatable {
        let title: MusicLinkTitle
        let expires: Date
    }

    /// The live titles by key. `title(for:)` reads it, so a change parses the
    /// shown bodies again.
    private(set) var titles: [String: Entry] = [:]
    /// The expiry dates of the failed reads by key. Not observed: a failure
    /// changes nothing on screen.
    @ObservationIgnored private var failures: [String: Date] = [:]

    @ObservationIgnored private var fetch: Fetch?
    @ObservationIgnored private var cacheFile: URL?
    @ObservationIgnored private var report: @MainActor (String) -> Void = { _ in }
    @ObservationIgnored private let now: @Sendable () -> Date

    @ObservationIgnored private var reads: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var runningReads = 0
    @ObservationIgnored private var waitingReads: [CheckedContinuation<Void, Never>] = []
    /// Changes with each `configure`, so a read of a former session does not
    /// land in the new one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var cacheWrite: Task<Void, Never>?
    @ObservationIgnored private var cacheIsDirty = false

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Sets the read and the cache file, and loads the file. Call it when a
    /// session starts, before a timeline shows, and with nils on sign-out.
    /// Drops what the store held before.
    ///
    /// - Parameters:
    ///   - cacheFile: The cache file, or nil for no cache.
    ///   - fetch: The preview read, or nil for no reads.
    ///   - report: Takes one line for the log when a read fails. The line
    ///     holds an error name only.
    public func configure(
        cacheFile: URL?,
        fetch: Fetch?,
        report: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        generation += 1
        reads.values.forEach { $0.cancel() }
        reads = [:]
        self.cacheFile = cacheFile
        self.fetch = fetch
        self.report = report
        cacheIsDirty = false
        let file = cacheFile.flatMap(Self.readCache(at:))
        let date = now()
        titles = (file?.titles ?? [:]).filter { $0.value.expires > date }
        failures = (file?.failures ?? [:]).filter { $0.value > date }
    }

    /// The live title of `link`, or nil: a link that is not a Spotify link,
    /// and a link with no title yet.
    public func title(for link: MusicLink) -> MusicLinkTitle? {
        guard link.service == .spotify, let key = Self.cacheKey(for: link.canonicalURL),
              let entry = titles[key], entry.expires > now()
        else { return nil }
        return entry.title
    }

    /// Reads the title of `link` if the store has no live answer for it and
    /// no read in flight. Does nothing for a link that is not a Spotify link,
    /// and before `configure` gives a read.
    ///
    /// - Returns: The read, for a test to wait on. A second call while the
    ///   read is in flight returns the same task.
    @discardableResult
    public func load(_ link: MusicLink) -> Task<Void, Never>? {
        guard link.service == .spotify, let fetch, let key = Self.cacheKey(for: link.canonicalURL) else { return nil }
        if let read = reads[key] {
            return read
        }
        let date = now()
        if let entry = titles[key], entry.expires > date {
            return nil
        }
        if let expires = failures[key], expires > date {
            return nil
        }
        let generation = generation
        let url = link.canonicalURL
        let kind = link.kind
        let read = Task {
            await self.acquireReadSlot()
            defer { self.releaseReadSlot() }
            guard !Task.isCancelled, generation == self.generation else { return }
            let outcome: Result<Data, Error>
            do {
                outcome = try await .success(fetch(url))
            } catch {
                outcome = .failure(error)
            }
            guard generation == self.generation else { return }
            self.finish(key: key, kind: kind, outcome: outcome)
        }
        reads[key] = read
        return read
    }

    /// Records `title` for `link` as a read would. For tests and previews.
    public func remember(_ title: MusicLinkTitle, for link: MusicLink) {
        guard let key = Self.cacheKey(for: link.canonicalURL) else { return }
        titles[key] = Entry(title: title, expires: now().addingTimeInterval(Self.titleLifetime))
    }

    /// True if a failed read of `link` is still live.
    public func hasLiveFailure(for link: MusicLink) -> Bool {
        guard let key = Self.cacheKey(for: link.canonicalURL), let expires = failures[key] else { return false }
        return expires > now()
    }

    private func finish(key: String, kind: MusicLink.Kind, outcome: Result<Data, Error>) {
        reads[key] = nil
        let date = now()
        switch outcome {
        case let .success(data):
            if let title = MusicLinkTitle.parse(data, kind: kind) {
                failures[key] = nil
                titles[key] = Entry(title: title, expires: date.addingTimeInterval(Self.titleLifetime))
                NotificationCenter.default.post(
                    name: Self.titlesDidChange,
                    object: self,
                    userInfo: [Self.changedKeysKey: [key]]
                )
            } else {
                failures[key] = date.addingTimeInterval(Self.failureLifetime)
                report("music link title: the preview has no title")
            }
        case let .failure(error):
            let lifetime = MusicLinkPreviewFailure.isTransient(error) ? Self.transportFailureLifetime : Self.failureLifetime
            failures[key] = date.addingTimeInterval(lifetime)
            report("music link title: \(MusicLinkPreviewFailure.logName(of: error))")
        }
        writeCache()
    }

    // MARK: - Read slots

    private func acquireReadSlot() async {
        if runningReads < Self.maxConcurrentReads {
            runningReads += 1
            return
        }
        await withCheckedContinuation { waitingReads.append($0) }
    }

    /// Hands the slot to the first waiting read, or frees it.
    private func releaseReadSlot() {
        if waitingReads.isEmpty {
            runningReads -= 1
        } else {
            waitingReads.removeFirst().resume()
        }
    }

    // MARK: - Keys

    /// The cache key of a link: the URL with a lowercase scheme and host, and
    /// with no query, no fragment, no user, no port, and no trailing slash.
    /// The path keeps its case: a Spotify ID is case-sensitive. Nil for a URL
    /// with no scheme or host.
    public nonisolated static func cacheKey(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        return "\(scheme)://\(host)\(path)"
    }

    /// True if an HTML body can hold a link of one of `keys`: it holds the
    /// last path part of the key (for Spotify, the 22-character ID).
    public nonisolated static func body(_ html: String, mayHoldAnyOf keys: [String]) -> Bool {
        keys.contains { key in
            guard let id = key.split(separator: "/").last, !id.isEmpty else { return false }
            return html.contains(id)
        }
    }

    // MARK: - Cache file

    struct CacheFile: Codable, Equatable {
        var version = 1
        var titles: [String: Entry]
        var failures: [String: Date]
    }

    /// Writes the live entries to the cache file. One writer: a change
    /// during a write starts one more write after it.
    private func writeCache() {
        guard let cacheFile else { return }
        cacheIsDirty = true
        guard cacheWrite == nil else { return }
        let generation = generation
        cacheWrite = Task {
            while self.cacheIsDirty, generation == self.generation {
                self.cacheIsDirty = false
                let file = self.liveCacheFile()
                if let problem = await Self.write(file, to: cacheFile) {
                    self.report("music link title: failed to write the cache: \(problem)")
                }
            }
            self.cacheWrite = nil
        }
    }

    /// The live entries, at most `capacity`: the ones that expire last.
    func liveCacheFile() -> CacheFile {
        let date = now()
        var liveTitles = titles.filter { $0.value.expires > date }
        var liveFailures = failures.filter { $0.value > date }
        let count = liveTitles.count + liveFailures.count
        if count > Self.capacity {
            let expiries = (liveTitles.map(\.value.expires) + liveFailures.map(\.value)).sorted(by: >)
            let cutoff = expiries[Self.capacity - 1]
            liveTitles = liveTitles.filter { $0.value.expires >= cutoff }
            liveFailures = liveFailures.filter { $0.value >= cutoff }
        }
        return CacheFile(titles: liveTitles, failures: liveFailures)
    }

    nonisolated static func readCache(at url: URL) -> CacheFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheFile.self, from: data)
    }

    /// - Returns: nil, or what went wrong, safe for the log.
    private nonisolated static func write(_ file: CacheFile, to url: URL) async -> String? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(file).write(to: url, options: .atomic)
            return nil
        } catch {
            let nsError = error as NSError
            return "\(nsError.domain) \(nsError.code)"
        }
    }

    /// Waits for the cache write in flight. After `configure`, no new write
    /// starts for the former file.
    public func waitForCacheWrite() async {
        await cacheWrite?.value
    }
}
