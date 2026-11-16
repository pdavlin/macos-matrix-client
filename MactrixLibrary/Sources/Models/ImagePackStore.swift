import Foundation

/// The image packs of the spaces that hold the open chats (MATRIX-155), and
/// the emoji learned from their messages (MATRIX-161).
///
/// A bridge puts each chat of a Slack workspace in the workspace's space, and
/// writes the workspace's custom emoji into that space's state. For a room,
/// the store finds the parent spaces, then loads each space's packs: first
/// from one JSON cache file per space, then from the homeserver. The store
/// has no SDK and no network of its own: `Source` gives it the parent lookup,
/// the state read (`ImagePackStateReader`), and the cache folder, so tests run
/// from fixtures.
///
/// Rules:
/// - The homeserver read of a space runs when the last good read is older
///   than `refreshInterval`, or was never made, and on each `refresh`. A
///   space has one read in flight: a second `load` in that time is dropped,
///   and a second `refresh` waits for the read in flight.
/// - After `maxFailedReads` failed reads in a row, the next `load` reads
///   again only when `refreshInterval` has passed since the last failure.
///   `refresh` always reads.
/// - A read that fails is reported and leaves the packs in use as they are.
/// - "No parent space" is not kept: the SDK gives that answer until its space
///   graph is ready (`RoomAccountNames`), so the next call asks again.
/// - `learn` records the emoji of a message body for the parent spaces of
///   the message's room (`LearnedEmoji` has the rules). A room with no known
///   parent space records nothing; the emoji wait in memory in case the
///   parent lookup has not answered yet.
/// - The cache file holds the parsed packs (shortcodes and `mxc://` URIs)
///   and, apart from them, the learned emoji. It never holds the room state.
///
/// Usage (in `Core`):
/// ```swift
/// await store.load(roomId: room.id, from: source)
/// let packs = store.packs(forRoom: room.id)
/// ```
@MainActor @Observable
public final class ImagePackStore {
    /// A parent space of a room.
    public struct Space: Equatable, Sendable {
        public let id: String
        /// The space's name: the title of a pack that has no name.
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// What the store reads from.
    public struct Source: Sendable {
        /// The folder of the cache files, or nil for no cache.
        public let cacheDirectory: URL?
        /// The joined parent spaces of a room.
        public let parentSpaces: @MainActor (_ roomId: String) async throws -> [Space]
        /// The state of a space, as `ImagePack.parse(roomState:)` reads it.
        public let fetchState: @MainActor (_ spaceId: String) async throws -> Data
        /// Takes one line for the log when a read fails. The line holds a
        /// room ID and an error name, never a token or a response body.
        public let report: @MainActor (String) -> Void

        public init(
            cacheDirectory: URL?,
            parentSpaces: @escaping @MainActor (_ roomId: String) async throws -> [Space],
            fetchState: @escaping @MainActor (_ spaceId: String) async throws -> Data,
            report: @escaping @MainActor (String) -> Void
        ) {
            self.cacheDirectory = cacheDirectory
            self.parentSpaces = parentSpaces
            self.fetchState = fetchState
            self.report = report
        }
    }

    /// The state of the "Refresh Custom Emoji" command for one room.
    public enum RefreshStatus: Equatable, Sendable {
        /// The read is in flight.
        case busy
        /// The read gave the packs. The count is every emoji the room can
        /// use now, imported and learned.
        case loaded(emojiCount: Int)
        /// The read of at least one parent space failed.
        case failed
    }

    /// How old the last good read of a space can be before a `load` reads
    /// the homeserver again.
    public static let refreshInterval: TimeInterval = 5 * 60

    /// The failed reads in a row after which a space waits `refreshInterval`.
    public static let maxFailedReads = 3

    /// The imported packs by space ID. A space that was read and has no pack
    /// has an empty list.
    public private(set) var packsBySpace: [String: [ImagePack]] = [:]
    /// The learned emoji by space ID.
    public private(set) var learnedBySpace: [String: LearnedEmoji] = [:]
    /// The parent space IDs by room ID, for the rooms that have a parent.
    public private(set) var spacesByRoom: [String: [String]] = [:]
    /// The refresh command's state by room ID. No entry means idle.
    public private(set) var refreshStatusByRoom: [String: RefreshStatus] = [:]
    /// What `packs(forRoom:)` gives for each space: the imported packs with
    /// the learned emoji merged in.
    private var shownPacksBySpace: [String: [ImagePack]] = [:]

    private struct CacheTarget {
        let file: URL
        let report: @MainActor (String) -> Void
    }

    private let now: @MainActor () -> Date
    @ObservationIgnored private var spaces: [String: Space] = [:]
    @ObservationIgnored private var resolvingRooms: Set<String> = []
    @ObservationIgnored private var importedShortcodes: [String: Set<String>] = [:]
    @ObservationIgnored private var lastGoodRead: [String: Date] = [:]
    @ObservationIgnored private var lastFailedRead: [String: Date] = [:]
    @ObservationIgnored private var failedReads: [String: Int] = [:]
    @ObservationIgnored private var stateReads: [String: Task<Bool, Never>] = [:]
    /// The cache read of each space. A finished task stays, so the file is
    /// read once and every caller waits for the same read.
    @ObservationIgnored private var cacheReads: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var cacheReadSpaces: Set<String> = []
    @ObservationIgnored private var cacheTargets: [String: CacheTarget] = [:]
    @ObservationIgnored private var unwrittenSpaces: Set<String> = []
    @ObservationIgnored private var cacheWrites: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var waitingByRoom: [String: [ImagePackEmoji]] = [:]
    @ObservationIgnored private var waitingBySpace: [String: [ImagePackEmoji]] = [:]

    /// - Parameter now: The clock. Tests give their own.
    public init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    /// The packs a reaction or a message in `roomId` can use: the packs of
    /// the room's parent spaces, with the learned emoji. Empty until `load`
    /// found them, and for a room with no pack. The read is observable.
    public func packs(forRoom roomId: String) -> [ImagePack] {
        (spacesByRoom[roomId] ?? []).flatMap { shownPacksBySpace[$0] ?? [] }
    }

    /// Whether the room has a known parent space, so a refresh has something
    /// to read. The read is observable.
    public func hasSpace(forRoom roomId: String) -> Bool {
        spacesByRoom[roomId]?.isEmpty == false
    }

    /// Loads the packs of the room's parent spaces. Safe to call on each
    /// chat open, each picker open, and each open of the composer's emoji
    /// list: see the rules on the type.
    ///
    /// - Parameters:
    ///   - roomId: The room of the chat.
    ///   - refresh: Reads the parent spaces and the homeserver again.
    ///   - source: Where to read from.
    public func load(roomId: String, refresh: Bool = false, from source: Source) async {
        for space in await parentSpaces(of: roomId, refresh: refresh, from: source) {
            await loadPacks(of: space, force: refresh, from: source)
        }
    }

    /// The "Refresh Custom Emoji" command: reads the room's parent spaces
    /// and their state now, and keeps the outcome in `refreshStatusByRoom`
    /// until `clearRefreshStatus(forRoom:)`.
    ///
    /// - Returns: The outcome, or nil when the room has no parent space or a
    ///   refresh of the room is in flight already.
    @discardableResult
    public func refresh(roomId: String, from source: Source) async -> RefreshStatus? {
        guard refreshStatusByRoom[roomId] != .busy else { return nil }
        refreshStatusByRoom[roomId] = .busy
        let parents = await parentSpaces(of: roomId, refresh: true, from: source)
        guard !parents.isEmpty else {
            refreshStatusByRoom[roomId] = nil
            return nil
        }
        var succeeded = true
        for space in parents {
            let outcome: Bool? = await loadPacks(of: space, force: true, from: source)
            if outcome != true {
                succeeded = false
            }
        }
        let count = packs(forRoom: roomId).reduce(0) { $0 + $1.emoji.count }
        let status: RefreshStatus = succeeded ? .loaded(emojiCount: count) : .failed
        refreshStatusByRoom[roomId] = status
        return status
    }

    /// Removes the outcome of the last refresh of the room. A refresh in
    /// flight stays.
    public func clearRefreshStatus(forRoom roomId: String) {
        guard let status = refreshStatusByRoom[roomId], status != .busy else { return }
        refreshStatusByRoom[roomId] = nil
    }

    /// Records the custom emoji that a message body of `roomId` showed, for
    /// each parent space of the room. Cheap when the emoji are known.
    ///
    /// - Parameters:
    ///   - emoji: The emoji, see `LearnedEmoji.emoji(name:url:)`.
    ///   - roomId: The room of the message.
    public func learn(_ emoji: [ImagePackEmoji], roomId: String) {
        guard !emoji.isEmpty else { return }
        guard let spaceIds = spacesByRoom[roomId] else {
            waitingByRoom[roomId] = Self.newest((waitingByRoom[roomId] ?? []) + emoji)
            return
        }
        for spaceId in spaceIds {
            record(emoji, in: spaceId)
        }
    }

    /// Returns when every cache write that a change started is on disk.
    public func waitForCacheWrites() async {
        while let write = cacheWrites.values.first {
            await write.value
        }
    }

    // MARK: - Parent spaces

    private func parentSpaces(of roomId: String, refresh: Bool, from source: Source) async -> [Space] {
        let known = (spacesByRoom[roomId] ?? []).compactMap { spaces[$0] }
        if !refresh, !known.isEmpty { return known }
        guard resolvingRooms.insert(roomId).inserted else { return known }
        defer { resolvingRooms.remove(roomId) }
        do {
            let parents = try await source.parentSpaces(roomId)
            // An empty answer is not final: see the rules on the type.
            guard !parents.isEmpty else { return known }
            for parent in parents {
                spaces[parent.id] = parent
            }
            let parentIds = parents.map(\.id)
            if spacesByRoom[roomId] != parentIds {
                spacesByRoom[roomId] = parentIds
            }
            if let waiting = waitingByRoom.removeValue(forKey: roomId) {
                learn(waiting, roomId: roomId)
            }
            return parents
        } catch {
            source.report("failed to read the parent spaces of \(roomId): \(String(describing: error))")
            return known
        }
    }

    // MARK: - Reads

    /// - Returns: Whether the homeserver read succeeded, or nil when this
    ///   call made no read and waited for none.
    @discardableResult
    private func loadPacks(of space: Space, force: Bool, from source: Source) async -> Bool? {
        if cacheReads[space.id] == nil {
            cacheReads[space.id] = Task { await self.readCache(of: space, from: source) }
        }
        await cacheReads[space.id]?.value

        if let running = stateReads[space.id] {
            return force ? await running.value : nil
        }
        guard force || isReadDue(of: space.id) else { return nil }
        let read = Task { await self.readState(of: space, from: source) }
        stateReads[space.id] = read
        let succeeded = await read.value
        stateReads[space.id] = nil
        return succeeded
    }

    private func isReadDue(of spaceId: String) -> Bool {
        let time = now()
        if let last = lastGoodRead[spaceId], time.timeIntervalSince(last) < Self.refreshInterval {
            return false
        }
        guard failedReads[spaceId, default: 0] >= Self.maxFailedReads else { return true }
        guard let last = lastFailedRead[spaceId], time.timeIntervalSince(last) >= Self.refreshInterval else {
            return false
        }
        failedReads[spaceId] = nil
        return true
    }

    private func readState(of space: Space, from source: Source) async -> Bool {
        do {
            let state = try await source.fetchState(space.id)
            let packs = try ImagePack.parse(roomState: state).map { $0.named(fallback: space.name) }
            lastGoodRead[space.id] = now()
            failedReads[space.id] = nil
            lastFailedRead[space.id] = nil
            setImported(packs, of: space.id)
            writeCache(of: space.id)
            await cacheWrites[space.id]?.value
            return true
        } catch {
            failedReads[space.id, default: 0] += 1
            lastFailedRead[space.id] = now()
            source.report("failed to read the image packs of \(space.id): \(Self.name(of: error))")
            return false
        }
    }

    private func readCache(of space: Space, from source: Source) async {
        if let directory = source.cacheDirectory {
            let file = Self.cacheFile(for: space.id, in: directory)
            cacheTargets[space.id] = CacheTarget(file: file, report: source.report)
            if let cached = await Self.readCache(at: file) {
                if packsBySpace[space.id] == nil {
                    setImported(cached.packs, of: space.id)
                }
                var learned = LearnedEmoji(entries: cached.learned ?? [])
                learned.remove(imported: importedShortcodes[space.id] ?? [])
                if !learned.entries.isEmpty {
                    learnedBySpace[space.id] = learned
                    updateShownPacks(of: space.id)
                }
            }
        }
        cacheReadSpaces.insert(space.id)
        if let waiting = waitingBySpace.removeValue(forKey: space.id) {
            record(waiting, in: space.id)
        }
    }
}

// MARK: - Packs in use

extension ImagePackStore {
    private func setImported(_ packs: [ImagePack], of spaceId: String) {
        if packsBySpace[spaceId] != packs {
            packsBySpace[spaceId] = packs
        }
        let shortcodes = Set(packs.flatMap { $0.emoji.map(\.shortcode) })
        importedShortcodes[spaceId] = shortcodes
        if var learned = learnedBySpace[spaceId], learned.remove(imported: shortcodes) {
            learnedBySpace[spaceId] = learned
        }
        updateShownPacks(of: spaceId)
    }

    private func record(_ emoji: [ImagePackEmoji], in spaceId: String) {
        // The learned emoji of the cache file come first: a write before the
        // file was read would lose them.
        guard cacheReadSpaces.contains(spaceId) else {
            waitingBySpace[spaceId] = Self.newest((waitingBySpace[spaceId] ?? []) + emoji)
            return
        }
        var learned = learnedBySpace[spaceId] ?? LearnedEmoji()
        let imported = importedShortcodes[spaceId] ?? []
        var changed = false
        for item in emoji where learned.record(item, imported: imported) {
            changed = true
        }
        guard changed else { return }
        learnedBySpace[spaceId] = learned
        updateShownPacks(of: spaceId)
        writeCache(of: spaceId)
    }

    private func updateShownPacks(of spaceId: String) {
        let shown = ImagePack.merging(
            learned: learnedBySpace[spaceId]?.entries ?? [],
            into: packsBySpace[spaceId] ?? [],
            fallbackName: spaces[spaceId]?.name
        )
        if shownPacksBySpace[spaceId] != shown {
            shownPacksBySpace[spaceId] = shown
        }
    }

    private static func newest(_ emoji: [ImagePackEmoji]) -> [ImagePackEmoji] {
        Array(emoji.suffix(LearnedEmoji.capacity))
    }
}

// MARK: - Cache file

extension ImagePackStore {
    /// Version 1 (MATRIX-155) has `packs` only. Version 2 adds `learned`,
    /// oldest first. A version 1 file loads with no learned emoji.
    private struct CacheFile: Codable {
        var version = 2
        let packs: [ImagePack]
        var learned: [ImagePackEmoji]?
    }

    /// The cache file of a space: `<directory>/<percent-encoded space ID>.json`.
    public nonisolated static func cacheFile(for spaceId: String, in directory: URL) -> URL {
        let name = spaceId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "space"
        return directory.appending(component: "\(name).json")
    }

    /// Writes the space's packs and learned emoji to its cache file. One
    /// writer per space: a change during a write starts one more write after
    /// it, so the file ends with the newest state.
    private func writeCache(of spaceId: String) {
        guard let target = cacheTargets[spaceId] else { return }
        unwrittenSpaces.insert(spaceId)
        guard cacheWrites[spaceId] == nil else { return }
        cacheWrites[spaceId] = Task {
            while self.unwrittenSpaces.remove(spaceId) != nil {
                let file = CacheFile(
                    packs: self.packsBySpace[spaceId] ?? [],
                    learned: self.learnedBySpace[spaceId]?.entries ?? []
                )
                if let problem = await Self.write(file, to: target.file) {
                    target.report("failed to write the image pack cache of \(spaceId): \(problem)")
                }
            }
            self.cacheWrites[spaceId] = nil
        }
    }

    private nonisolated static func readCache(at url: URL) async -> CacheFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheFile.self, from: data)
    }

    /// - Returns: nil, or what went wrong.
    private nonisolated static func write(_ file: CacheFile, to url: URL) async -> String? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(file).write(to: url, options: .atomic)
            return nil
        } catch {
            return name(of: error)
        }
    }

    /// A short name for an error, safe for the log: the case of our own
    /// errors, else the error's domain and code. Never the description, which
    /// can hold a URL.
    private nonisolated static func name(of error: Error) -> String {
        switch error {
        case let failure as ImagePackStateReader.Failure:
            return String(describing: failure)
        case is ImagePack.MalformedRoomState:
            return "the room state is not a JSON array of events"
        default:
            let nsError = error as NSError
            return "\(nsError.domain) \(nsError.code)"
        }
    }
}
