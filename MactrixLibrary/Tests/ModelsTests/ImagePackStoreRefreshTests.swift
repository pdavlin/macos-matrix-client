import Foundation
import Models
import Testing

struct PackStoreReadFailed: Error {}

/// The clock the store reads.
@MainActor
final class PackStoreClock {
    var time = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func advance(by seconds: TimeInterval) {
        time += seconds
    }
}

/// The stubs behind a `Source`, with call counts and a gate that holds
/// a state read open.
@MainActor
final class PackStoreBackend {
    var parents: [String: [ImagePackStore.Space]] = [:]
    var states: [String: Result<Data, Error>] = [:]
    var parentReads = 0
    var stateReads: [String] = []
    var reports: [String] = []
    var holdsStateReads = false
    var heldReads: [CheckedContinuation<Void, Never>] = []
    let cacheDirectory: URL?

    init(cacheDirectory: URL?) {
        self.cacheDirectory = cacheDirectory
    }

    var source: ImagePackStore.Source {
        ImagePackStore.Source(
            cacheDirectory: cacheDirectory,
            parentSpaces: { roomId in
                self.parentReads += 1
                return self.parents[roomId] ?? []
            },
            fetchState: { spaceId in
                self.stateReads.append(spaceId)
                if self.holdsStateReads {
                    await withCheckedContinuation { self.heldReads.append($0) }
                }
                return try (self.states[spaceId] ?? .failure(PackStoreReadFailed())).get()
            },
            report: { self.reports.append($0) }
        )
    }

    func releaseStateReads() {
        holdsStateReads = false
        for held in heldReads {
            held.resume()
        }
        heldReads = []
    }
}

/// What the store tests of MATRIX-161 share: the rooms, the spaces, and the
/// stubs.
@MainActor
protocol ImagePackStoreFixture {}

extension ImagePackStoreFixture {
    static var space: ImagePackStore.Space { ImagePackStore.Space(id: "!space:example.org", name: "Acme") }
    static var otherSpace: ImagePackStore.Space { ImagePackStore.Space(id: "!other-space:example.org", name: "Other") }
    static var room: String { "!channel:example.org" }
    static var otherRoom: String { "!elsewhere:example.org" }

    static func state(shortcodes: [String]) -> Data {
        let images = shortcodes.map { "\"\($0)\": {\"url\": \"mxc://example.org/\($0)\"}" }.joined(separator: ", ")
        return Data("""
        [{"type": "m.room.image_pack", "state_key": "acme", "content": {"images": {\(images)}, "pack": {"display_name": "Acme emojis"}}}]
        """.utf8)
    }

    static func emoji(_ shortcode: String, _ media: String? = nil) -> ImagePackEmoji {
        ImagePackEmoji(shortcode: shortcode, url: "mxc://example.org/\(media ?? shortcode)")
    }

    func makeBackend(cache: Bool = false) throws -> PackStoreBackend {
        var directory: URL?
        if cache {
            let url = FileManager.default.temporaryDirectory.appending(component: "ImagePackStoreRefreshTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            directory = url
        }
        let backend = PackStoreBackend(cacheDirectory: directory)
        backend.parents[Self.room] = [Self.space]
        backend.parents[Self.otherRoom] = [Self.otherSpace]
        backend.states[Self.space.id] = .success(Self.state(shortcodes: ["shipit", "parrot"]))
        backend.states[Self.otherSpace.id] = .success(Data("[]".utf8))
        return backend
    }

    func makeStore(_ clock: PackStoreClock) -> ImagePackStore {
        ImagePackStore(now: { clock.time })
    }

    func shortcodes(_ store: ImagePackStore, room: String = Self.room) -> [String] {
        store.packs(forRoom: room).flatMap { $0.emoji.map(\.shortcode) }
    }

    func cacheText(_ backend: PackStoreBackend, space: ImagePackStore.Space = Self.space) throws -> String {
        let directory = try #require(backend.cacheDirectory)
        return try String(contentsOf: ImagePackStore.cacheFile(for: space.id, in: directory), encoding: .utf8)
    }

    func removeCache(_ backend: PackStoreBackend) {
        if let directory = backend.cacheDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

/// MATRIX-161: the store reads a space again while the app runs, and has a
/// forced refresh. The clock and every source are stubs: no SDK, no network.
@MainActor
struct ImagePackStoreRefreshTests: ImagePackStoreFixture {
    // MARK: - The interval

    @Test func readsASpaceAgainWhenTheLastGoodReadIsOlderThanTheInterval() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = makeStore(clock)

        await store.load(roomId: Self.room, from: backend.source)
        backend.states[Self.space.id] = .success(Self.state(shortcodes: ["shipit", "parrot", "newcomer"]))

        clock.advance(by: ImagePackStore.refreshInterval - 1)
        await store.load(roomId: Self.room, from: backend.source)
        #expect(backend.stateReads.count == 1)
        #expect(shortcodes(store) == ["parrot", "shipit"])

        clock.advance(by: 1)
        await store.load(roomId: Self.room, from: backend.source)
        #expect(backend.stateReads.count == 2)
        #expect(shortcodes(store) == ["newcomer", "parrot", "shipit"])

        // The new read starts a new interval.
        await store.load(roomId: Self.room, from: backend.source)
        #expect(backend.stateReads.count == 2)
        // The parent spaces of a room are read once.
        #expect(backend.parentReads == 1)
    }

    @Test func theIntervalIsFiveMinutes() {
        #expect(ImagePackStore.refreshInterval == 300)
    }

    // MARK: - One read in flight

    @Test func aSecondLoadDuringAReadIsDroppedAndASecondRefreshJoinsIt() async throws {
        let backend = try makeBackend()
        backend.holdsStateReads = true
        let store = makeStore(PackStoreClock())
        let source = backend.source

        let first = Task { await store.load(roomId: Self.room, from: source) }
        while backend.heldReads.isEmpty {
            await Task.yield()
        }

        // A second trigger returns at once, with no read of its own.
        await store.load(roomId: Self.room, from: source)
        #expect(backend.stateReads.count == 1)

        // A forced refresh waits for the read in flight.
        let forced = Task { await store.refresh(roomId: Self.room, from: source) }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(backend.stateReads.count == 1)
        #expect(store.refreshStatusByRoom[Self.room] == .busy)

        backend.releaseStateReads()
        await first.value
        let outcome = await forced.value

        #expect(backend.stateReads.count == 1)
        #expect(outcome == .loaded(emojiCount: 2))
        #expect(shortcodes(store) == ["parrot", "shipit"])
    }

    // MARK: - Failed reads

    @Test func afterThreeFailedReadsASpaceWaitsTheInterval() async throws {
        let backend = try makeBackend()
        backend.states[Self.space.id] = .failure(PackStoreReadFailed())
        let clock = PackStoreClock()
        let store = makeStore(clock)

        for _ in 0 ..< ImagePackStore.maxFailedReads + 3 {
            await store.load(roomId: Self.room, from: backend.source)
        }
        #expect(backend.stateReads.count == ImagePackStore.maxFailedReads)

        clock.advance(by: ImagePackStore.refreshInterval - 1)
        await store.load(roomId: Self.room, from: backend.source)
        #expect(backend.stateReads.count == ImagePackStore.maxFailedReads)

        clock.advance(by: 1)
        for _ in 0 ..< ImagePackStore.maxFailedReads + 3 {
            await store.load(roomId: Self.room, from: backend.source)
        }
        #expect(backend.stateReads.count == 2 * ImagePackStore.maxFailedReads)
    }

    @Test func aGoodReadEndsTheCountOfFailedReads() async throws {
        let backend = try makeBackend()
        backend.states[Self.space.id] = .failure(PackStoreReadFailed())
        let clock = PackStoreClock()
        let store = makeStore(clock)
        for _ in 0 ..< ImagePackStore.maxFailedReads - 1 {
            await store.load(roomId: Self.room, from: backend.source)
        }

        backend.states[Self.space.id] = .success(Self.state(shortcodes: ["shipit"]))
        await store.load(roomId: Self.room, from: backend.source)
        #expect(shortcodes(store) == ["shipit"])

        // After the interval, the space has its full number of tries again.
        backend.states[Self.space.id] = .failure(PackStoreReadFailed())
        clock.advance(by: ImagePackStore.refreshInterval)
        for _ in 0 ..< ImagePackStore.maxFailedReads + 2 {
            await store.load(roomId: Self.room, from: backend.source)
        }
        #expect(backend.stateReads.count == 2 * ImagePackStore.maxFailedReads)
        #expect(shortcodes(store) == ["shipit"])
    }

    // MARK: - The refresh command

    @Test func aRefreshReadsNowAndGivesTheEmojiCount() async throws {
        let backend = try makeBackend()
        let store = makeStore(PackStoreClock())
        await store.load(roomId: Self.room, from: backend.source)
        #expect(store.hasSpace(forRoom: Self.room))

        backend.states[Self.space.id] = .success(Self.state(shortcodes: ["shipit", "parrot", "newcomer"]))
        let outcome = await store.refresh(roomId: Self.room, from: backend.source)

        #expect(outcome == .loaded(emojiCount: 3))
        #expect(backend.stateReads.count == 2)
        // The refresh reads the parent spaces again too.
        #expect(backend.parentReads == 2)
        #expect(store.refreshStatusByRoom[Self.room] == .loaded(emojiCount: 3))
        #expect(shortcodes(store) == ["newcomer", "parrot", "shipit"])

        store.clearRefreshStatus(forRoom: Self.room)
        #expect(store.refreshStatusByRoom[Self.room] == nil)
    }

    @Test func aRefreshThatFailsSaysSoAndKeepsThePack() async throws {
        let backend = try makeBackend()
        let store = makeStore(PackStoreClock())
        await store.load(roomId: Self.room, from: backend.source)

        backend.states[Self.space.id] = .failure(ImagePackStateReader.Failure.status(502))
        let outcome = await store.refresh(roomId: Self.room, from: backend.source)

        #expect(outcome == .failed)
        #expect(store.refreshStatusByRoom[Self.room] == .failed)
        #expect(shortcodes(store) == ["parrot", "shipit"])
        #expect(backend.reports.count == 1)
    }

    @Test func aRefreshReadsASpaceThatWaitsAfterFailedReads() async throws {
        let backend = try makeBackend()
        backend.states[Self.space.id] = .failure(PackStoreReadFailed())
        let store = makeStore(PackStoreClock())
        for _ in 0 ..< ImagePackStore.maxFailedReads + 1 {
            await store.load(roomId: Self.room, from: backend.source)
        }

        backend.states[Self.space.id] = .success(Self.state(shortcodes: ["shipit"]))
        let outcome = await store.refresh(roomId: Self.room, from: backend.source)

        #expect(outcome == .loaded(emojiCount: 1))
        #expect(backend.stateReads.count == ImagePackStore.maxFailedReads + 1)
    }

    @Test func aRefreshInARoomWithNoParentSpaceDoesNothing() async throws {
        let backend = try makeBackend()
        backend.parents[Self.room] = []
        let store = makeStore(PackStoreClock())

        let outcome = await store.refresh(roomId: Self.room, from: backend.source)

        #expect(outcome == nil)
        #expect(!store.hasSpace(forRoom: Self.room))
        #expect(store.refreshStatusByRoom[Self.room] == nil)
        #expect(backend.stateReads.isEmpty)
    }

    @Test func clearingLeavesARefreshInFlight() async throws {
        let backend = try makeBackend()
        backend.holdsStateReads = true
        let store = makeStore(PackStoreClock())
        let source = backend.source

        let refresh = Task { await store.refresh(roomId: Self.room, from: source) }
        while backend.heldReads.isEmpty {
            await Task.yield()
        }
        store.clearRefreshStatus(forRoom: Self.room)
        #expect(store.refreshStatusByRoom[Self.room] == .busy)
        // A second refresh of the room during the first makes no read.
        let second = await store.refresh(roomId: Self.room, from: source)
        #expect(second == nil)
        #expect(backend.stateReads.count == 1)

        backend.releaseStateReads()
        let outcome = await refresh.value
        #expect(outcome == .loaded(emojiCount: 2))
    }
}
