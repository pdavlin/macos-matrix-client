import Foundation
import Models
import Testing

/// A clock a test moves by hand.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { date += interval }
    }
}

/// Lines that a closure collects.
private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var all: [String] {
        lock.withLock { stored }
    }

    func append(_ lines: [String]) {
        lock.withLock { stored += lines }
    }
}

/// A preview read that counts its calls, and that can hold each call until
/// the test releases it.
@MainActor
private final class StubPreviews {
    var answer: (URL) throws -> Data
    var holds = false
    private(set) var calls: [URL] = []
    private(set) var running = 0
    private(set) var maxRunning = 0
    private var held: [CheckedContinuation<Void, Never>] = []

    init(answer: @escaping (URL) throws -> Data) {
        self.answer = answer
    }

    var heldCount: Int {
        held.count
    }

    func fetch(_ url: URL) async throws -> Data {
        calls.append(url)
        running += 1
        maxRunning = max(maxRunning, running)
        defer { running -= 1 }
        if holds {
            await withCheckedContinuation { held.append($0) }
        }
        return try answer(url)
    }

    func releaseAll() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }
}

/// MATRIX-191: the store of the music link titles. A stub stands in for the
/// homeserver, and a test clock for the time.
@MainActor
struct MusicLinkTitleStoreTests {
    private static let trackURL = "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=abc"
    private static let albumURL = "https://open.spotify.com/album/6N9PS4QXF1D0OWPk0Sxtb4"

    private let clock = TestClock()

    private func store() -> MusicLinkTitleStore {
        let clock = clock
        return MusicLinkTitleStore(now: { clock.now })
    }

    private func link(_ string: String = trackURL) throws -> MusicLink {
        try #require(MusicLink.classify(string))
    }

    /// A Spotify track link with a made-up ID.
    private func track(_ index: Int) throws -> MusicLink {
        let id = String(format: "%022d", index)
        return try link("https://open.spotify.com/track/\(id)")
    }

    private func configure(_ store: MusicLinkTitleStore, _ stub: StubPreviews, cacheFile: URL? = nil) {
        store.configure(cacheFile: cacheFile, fetch: { try await stub.fetch($0) })
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(component: "MusicLinkTitleStoreTests-\(UUID().uuidString)")
            .appending(component: "MusicLinkTitles.json")
    }

    // MARK: Keys

    @Test func theCacheKeyDropsQueryFragmentAndTrailingSlashAndLowercasesTheHost() throws {
        let url = try #require(URL(string: "HTTPS://Open.Spotify.COM/track/4cOdK2wGLETKBW3PvgPWqT/?si=abc&utm=x#top"))
        #expect(MusicLinkTitleStore.cacheKey(for: url) == "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test func theCacheKeyKeepsTheCaseOfThePath() throws {
        let url = try #require(URL(string: "https://open.spotify.com/album/6N9PS4QXF1D0OWPk0Sxtb4"))
        #expect(MusicLinkTitleStore.cacheKey(for: url) == "https://open.spotify.com/album/6N9PS4QXF1D0OWPk0Sxtb4")
    }

    @Test func aPostedLinkAndItsCanonicalFormShareAKey() throws {
        let posted = try #require(URL(string: "https://open.spotify.com/intl-de/track/4cOdK2wGLETKBW3PvgPWqT?si=abc"))
        let canonical = try link(Self.trackURL).canonicalURL
        let fromPosted = try link(posted.absoluteString).canonicalURL
        #expect(MusicLinkTitleStore.cacheKey(for: canonical) == MusicLinkTitleStore.cacheKey(for: fromPosted))
    }

    @Test func aBodyMayHoldAKeyWhenItHoldsTheID() {
        let keys = ["https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"]
        #expect(MusicLinkTitleStore.body(#"<a href="https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=1">x</a>"#, mayHoldAnyOf: keys))
        #expect(!MusicLinkTitleStore.body("<p>no link</p>", mayHoldAnyOf: keys))
        #expect(!MusicLinkTitleStore.body("anything", mayHoldAnyOf: []))
    }

    // MARK: Reads

    @Test func aReadGivesTheTitleAndPostsTheKey() async throws {
        let store = store()
        let stub = StubPreviews { _ in Data(MusicLinkTitleTests.trackJSON.utf8) }
        configure(store, stub)
        let link = try link()

        let posted = Lines()
        let observer = NotificationCenter.default.addObserver(
            forName: MusicLinkTitleStore.titlesDidChange,
            object: store,
            queue: nil
        ) { note in
            posted.append(note.userInfo?[MusicLinkTitleStore.changedKeysKey] as? [String] ?? [])
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        #expect(store.title(for: link) == nil)
        await store.load(link)?.value

        #expect(store.title(for: link)?.text == "Rick Astley \u{00B7} Never Gonna Give You Up")
        #expect(stub.calls == [link.canonicalURL])
        #expect(posted.all == ["https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"])
        // A live title makes no second read.
        #expect(store.load(link) == nil)
        #expect(stub.calls.count == 1)
    }

    @Test func anAlbumReadUsesTheAlbumRules() async throws {
        let store = store()
        let stub = StubPreviews { _ in Data(MusicLinkTitleTests.albumJSON.utf8) }
        configure(store, stub)
        let album = try link(Self.albumURL)
        await store.load(album)?.value
        #expect(store.title(for: album)?.text == "Rick Astley \u{00B7} Whenever You Need Somebody")
    }

    @Test func aLinkThatIsNotSpotifyHasNoRead() throws {
        let store = store()
        let stub = StubPreviews { _ in Data() }
        configure(store, stub)
        let deezer = try link("https://www.deezer.com/track/3135556")
        #expect(store.load(deezer) == nil)
        #expect(stub.calls.isEmpty)
    }

    @Test func noReadBeforeConfigure() throws {
        #expect(try store().load(link()) == nil)
    }

    @Test func aTitleExpiresAfterItsLifetime() async throws {
        let store = store()
        let stub = StubPreviews { _ in Data(MusicLinkTitleTests.trackJSON.utf8) }
        configure(store, stub)
        let link = try link()
        await store.load(link)?.value

        clock.advance(by: MusicLinkTitleStore.titleLifetime - 1)
        #expect(store.title(for: link) != nil)
        clock.advance(by: 2)
        #expect(store.title(for: link) == nil)
        await store.load(link)?.value
        #expect(stub.calls.count == 2)
    }

    // MARK: Failures

    /// MATRIX-219: a Matrix error of the homeserver, and an answer with no
    /// preview, as `Core` maps them from the SDK.
    @Test(arguments: [MusicLinkPreviewFailure.homeserver(errcode: "M_UNKNOWN"), .noPreview])
    func aFailedReadIsKeptForAnHourThenReadAgain(failure: MusicLinkPreviewFailure) async throws {
        let store = store()
        let stub = StubPreviews { _ in throw failure }
        configure(store, stub)
        let link = try link()

        await store.load(link)?.value
        #expect(store.title(for: link) == nil)
        #expect(store.hasLiveFailure(for: link))
        #expect(store.load(link) == nil)

        clock.advance(by: MusicLinkTitleStore.failureLifetime - 1)
        #expect(store.load(link) == nil)
        #expect(stub.calls.count == 1)

        clock.advance(by: 2)
        #expect(!store.hasLiveFailure(for: link))
        stub.answer = { _ in Data(MusicLinkTitleTests.trackJSON.utf8) }
        await store.load(link)?.value
        #expect(stub.calls.count == 2)
        #expect(store.title(for: link) != nil)
        #expect(!store.hasLiveFailure(for: link))
    }

    @Test func aPreviewWithNoTitleIsAFailure() async throws {
        let store = store()
        let stub = StubPreviews { _ in Data(#"{"og:type": "website"}"#.utf8) }
        configure(store, stub)
        let link = try link()
        await store.load(link)?.value
        #expect(store.title(for: link) == nil)
        #expect(store.hasLiveFailure(for: link))
    }

    /// MATRIX-219: also the SDK's network error, as `Core` maps it.
    @Test(arguments: [URLError(.notConnectedToInternet), MusicLinkPreviewFailure.transport] as [any Error])
    func aTransportErrorIsKeptForAShorterTime(error: any Error) async throws {
        let store = store()
        let stub = StubPreviews { _ in throw error }
        configure(store, stub)
        let link = try link()
        await store.load(link)?.value
        #expect(store.hasLiveFailure(for: link))
        clock.advance(by: MusicLinkTitleStore.transportFailureLifetime + 1)
        #expect(!store.hasLiveFailure(for: link))
    }

    @Test func aFailureReportsANameWithNoToken() async throws {
        let store = store()
        let lines = Lines()
        store.configure(
            cacheFile: nil,
            fetch: { _ in throw MusicLinkPreviewFailure.homeserver(errcode: "M_UNKNOWN") },
            report: { lines.append([$0]) }
        )
        try await store.load(link())?.value
        #expect(lines.all == [#"music link title: homeserver(errcode: "M_UNKNOWN")"#])
    }

    // MARK: Coalescing and limit

    @Test func oneReadPerLinkAtATime() async throws {
        let store = store()
        let stub = StubPreviews { _ in Data(MusicLinkTitleTests.trackJSON.utf8) }
        stub.holds = true
        configure(store, stub)
        let link = try link()

        let first = try #require(store.load(link))
        let second = try #require(store.load(link))
        #expect(first == second)
        while stub.heldCount < 1 {
            await Task.yield()
        }
        stub.releaseAll()
        await first.value
        #expect(stub.calls.count == 1)
    }

    @Test func atMostFourReadsRunAtOnce() async throws {
        let store = store()
        let stub = StubPreviews { _ in Data(MusicLinkTitleTests.trackJSON.utf8) }
        stub.holds = true
        configure(store, stub)

        let reads = try (0 ..< 7).compactMap { try store.load(track($0)) }
        #expect(reads.count == 7)
        while stub.heldCount < MusicLinkTitleStore.maxConcurrentReads {
            await Task.yield()
        }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(stub.calls.count == MusicLinkTitleStore.maxConcurrentReads)

        while stub.calls.count < 7 || stub.heldCount > 0 {
            stub.releaseAll()
            await Task.yield()
        }
        for read in reads {
            await read.value
        }
        #expect(stub.calls.count == 7)
        #expect(stub.maxRunning == MusicLinkTitleStore.maxConcurrentReads)
    }

    // MARK: Cache file

    @Test func theCacheFileGivesTheTitleAtOnceInANewStore() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let first = store()
        let stub = StubPreviews { _ in Data(MusicLinkTitleTests.trackJSON.utf8) }
        configure(first, stub, cacheFile: file)
        let link = try link()
        await first.load(link)?.value
        await first.waitForCacheWrite()

        let second = store()
        let unused = StubPreviews { _ in Data() }
        configure(second, unused, cacheFile: file)
        #expect(second.title(for: link)?.name == "Never Gonna Give You Up")
        #expect(second.load(link) == nil)
        #expect(unused.calls.isEmpty)

        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("og:"))
    }

    @Test func theCacheFileKeepsFailuresAndDropsExpiredEntries() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let first = store()
        let stub = StubPreviews { _ in throw MusicLinkPreviewFailure.homeserver(errcode: "M_NOT_FOUND") }
        configure(first, stub, cacheFile: file)
        let link = try link()
        await first.load(link)?.value
        await first.waitForCacheWrite()

        let second = store()
        configure(second, stub, cacheFile: file)
        #expect(second.hasLiveFailure(for: link))

        clock.advance(by: MusicLinkTitleStore.failureLifetime + 1)
        let third = store()
        configure(third, stub, cacheFile: file)
        #expect(!third.hasLiveFailure(for: link))
    }

    @Test func configureDropsTheFormerSession() async throws {
        let store = store()
        let stub = StubPreviews { _ in Data(MusicLinkTitleTests.trackJSON.utf8) }
        configure(store, stub)
        let link = try link()
        await store.load(link)?.value
        #expect(store.title(for: link) != nil)

        store.configure(cacheFile: nil, fetch: nil)
        #expect(store.title(for: link) == nil)
        #expect(store.load(link) == nil)
    }

    @Test func rememberSetsATitle() throws {
        let store = store()
        let link = try link()
        store.remember(MusicLinkTitle(artist: "A", name: "B"), for: link)
        #expect(store.title(for: link)?.text == "A \u{00B7} B")
    }
}
