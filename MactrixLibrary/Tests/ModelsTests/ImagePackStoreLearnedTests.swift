import Foundation
import Models
import Testing

/// MATRIX-161: the store keeps the emoji learned from messages, apart from
/// the imported packs, in memory and in the cache file. The fixture is in
/// `ImagePackStoreRefreshTests.swift`.
@MainActor
struct ImagePackStoreLearnedTests: ImagePackStoreFixture {
    // MARK: - Learned emoji

    @Test func aLearnedEmojiShowsAtOnceInItsSpaceOnly() async throws {
        let backend = try makeBackend()
        let store = makeStore(PackStoreClock())
        await store.load(roomId: Self.room, from: backend.source)
        await store.load(roomId: Self.otherRoom, from: backend.source)

        store.learn([Self.emoji("newcomer")], roomId: Self.room)

        #expect(shortcodes(store) == ["newcomer", "parrot", "shipit"])
        #expect(store.packs(forRoom: Self.room).map(\.displayName) == ["Acme emojis"])
        #expect(store.packsBySpace[Self.space.id]?.first?.emoji.map(\.shortcode) == ["parrot", "shipit"])
        #expect(store.learnedBySpace[Self.space.id]?.entries == [Self.emoji("newcomer")])
        #expect(store.packs(forRoom: Self.otherRoom).isEmpty)
        // No request: learning reads nothing.
        #expect(backend.stateReads.count == 2)
    }

    @Test func aSpaceWithNoImportShowsItsLearnedEmojiUnderItsName() async throws {
        let backend = try makeBackend()
        let store = makeStore(PackStoreClock())
        await store.load(roomId: Self.otherRoom, from: backend.source)

        store.learn([Self.emoji("zebra"), Self.emoji("apple")], roomId: Self.otherRoom)

        let packs = store.packs(forRoom: Self.otherRoom)
        #expect(packs.map(\.displayName) == ["Other"])
        #expect(packs.first?.emoji.map(\.shortcode) == ["apple", "zebra"])
    }

    @Test func anImportedEntryWinsOverALearnedOne() async throws {
        let backend = try makeBackend()
        let store = makeStore(PackStoreClock())
        await store.load(roomId: Self.room, from: backend.source)

        store.learn([Self.emoji("parrot", "another-image")], roomId: Self.room)

        #expect(store.learnedBySpace[Self.space.id] == nil)
        #expect(store.packs(forRoom: Self.room).first?.emoji.first?.url == "mxc://example.org/parrot")
    }

    @Test func aNewURLReplacesTheLearnedEntry() async throws {
        let backend = try makeBackend()
        let store = makeStore(PackStoreClock())
        await store.load(roomId: Self.room, from: backend.source)

        store.learn([Self.emoji("newcomer", "v1")], roomId: Self.room)
        store.learn([Self.emoji("newcomer", "v2")], roomId: Self.room)

        #expect(store.learnedBySpace[Self.space.id]?.entries == [Self.emoji("newcomer", "v2")])
        #expect(store.packs(forRoom: Self.room).first?.emoji.first?.url == "mxc://example.org/v2")
    }

    @Test func aRoomWithNoParentSpaceRecordsNothing() async throws {
        let backend = try makeBackend(cache: true)
        backend.parents[Self.room] = []
        let store = makeStore(PackStoreClock())
        await store.load(roomId: Self.room, from: backend.source)

        store.learn([Self.emoji("newcomer")], roomId: Self.room)
        await store.waitForCacheWrites()

        #expect(store.packs(forRoom: Self.room).isEmpty)
        #expect(store.learnedBySpace.isEmpty)
        let directory = try #require(backend.cacheDirectory)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(files.isEmpty)
        removeCache(backend)
    }

    @Test func emojiSeenBeforeTheParentLookupAnswersAreRecordedWhenItDoes() async throws {
        let backend = try makeBackend()
        let store = makeStore(PackStoreClock())

        // The row draws before the chat's parent lookup has an answer.
        store.learn([Self.emoji("newcomer")], roomId: Self.room)
        #expect(store.learnedBySpace.isEmpty)

        await store.load(roomId: Self.room, from: backend.source)

        #expect(shortcodes(store) == ["newcomer", "parrot", "shipit"])
    }

    @Test func anImportThatHasTheEmojiTakesItOutOfTheLearnedSet() async throws {
        let backend = try makeBackend(cache: true)
        let store = makeStore(PackStoreClock())
        await store.load(roomId: Self.room, from: backend.source)
        store.learn([Self.emoji("newcomer", "learned"), Self.emoji("latecomer")], roomId: Self.room)

        backend.states[Self.space.id] = .success(Self.state(shortcodes: ["shipit", "parrot", "newcomer"]))
        await store.refresh(roomId: Self.room, from: backend.source)
        await store.waitForCacheWrites()

        // The import has "newcomer" now; it lacks "latecomer", which stays.
        #expect(store.learnedBySpace[Self.space.id]?.entries == [Self.emoji("latecomer")])
        #expect(shortcodes(store) == ["latecomer", "newcomer", "parrot", "shipit"])
        let newcomer = store.packs(forRoom: Self.room).first?.emoji.first { $0.shortcode == "newcomer" }
        #expect(newcomer?.url == "mxc://example.org/newcomer")
        let file = try JSONDecoder().decode(StoredFile.self, from: Data(cacheText(backend).utf8))
        #expect(file.learned == [Self.emoji("latecomer")])
        #expect(file.packs.first?.emoji.map(\.url).contains("mxc://example.org/learned") == false)
        removeCache(backend)
    }

    // MARK: - The cache file

    /// The file as `JSONDecoder` reads it, apart from the store's own type.
    private struct StoredFile: Decodable {
        let version: Int
        let packs: [ImagePack]
        let learned: [ImagePackEmoji]?
    }

    @Test func learnedEmojiPersistApartFromThePacks() async throws {
        let backend = try makeBackend(cache: true)
        let first = makeStore(PackStoreClock())
        await first.load(roomId: Self.room, from: backend.source)
        first.learn([Self.emoji("zebra"), Self.emoji("apple")], roomId: Self.room)
        await first.waitForCacheWrites()

        let file = try JSONDecoder().decode(StoredFile.self, from: Data(cacheText(backend).utf8))
        #expect(file.version == 2)
        #expect(file.packs.map(\.emoji) == [[Self.emoji("parrot"), Self.emoji("shipit")]])
        #expect(file.learned == [Self.emoji("zebra"), Self.emoji("apple")])

        // A new session with no homeserver: the cache gives both.
        backend.states[Self.space.id] = .failure(PackStoreReadFailed())
        let second = makeStore(PackStoreClock())
        await second.load(roomId: Self.room, from: backend.source)

        #expect(shortcodes(second) == ["apple", "parrot", "shipit", "zebra"])
        #expect(second.learnedBySpace[Self.space.id]?.entries == [Self.emoji("zebra"), Self.emoji("apple")])
        removeCache(backend)
    }

    @Test func aNewImportKeepsTheLearnedEmojiOfTheCacheFile() async throws {
        let backend = try makeBackend(cache: true)
        let first = makeStore(PackStoreClock())
        await first.load(roomId: Self.room, from: backend.source)
        first.learn([Self.emoji("zebra")], roomId: Self.room)
        await first.waitForCacheWrites()

        // A new session reads a newer import that lacks "zebra".
        backend.states[Self.space.id] = .success(Self.state(shortcodes: ["shipit", "parrot", "newcomer"]))
        let second = makeStore(PackStoreClock())
        await second.load(roomId: Self.room, from: backend.source)
        await second.waitForCacheWrites()

        #expect(shortcodes(second) == ["newcomer", "parrot", "shipit", "zebra"])
        let file = try JSONDecoder().decode(StoredFile.self, from: Data(cacheText(backend).utf8))
        #expect(file.learned == [Self.emoji("zebra")])
        #expect(file.packs.first?.emoji.map(\.shortcode) == ["newcomer", "parrot", "shipit"])
        removeCache(backend)
    }

    @Test func emojiLearnedDuringTheCacheReadDoNotLoseTheStoredOnes() async throws {
        let backend = try makeBackend(cache: true)
        let first = makeStore(PackStoreClock())
        await first.load(roomId: Self.room, from: backend.source)
        first.learn([Self.emoji("zebra")], roomId: Self.room)
        await first.waitForCacheWrites()

        // A new session: a row reports an emoji before the store read the file.
        let second = makeStore(PackStoreClock())
        second.learn([Self.emoji("apple")], roomId: Self.room)
        await second.load(roomId: Self.room, from: backend.source)
        await second.waitForCacheWrites()

        #expect(second.learnedBySpace[Self.space.id]?.entries == [Self.emoji("zebra"), Self.emoji("apple")])
        let file = try JSONDecoder().decode(StoredFile.self, from: Data(cacheText(backend).utf8))
        #expect(file.learned == [Self.emoji("zebra"), Self.emoji("apple")])
        removeCache(backend)
    }

    /// The exact bytes that the store of MATRIX-155 (main at 97def6b) wrote:
    /// version 1, packs only.
    private static let versionOneFile = """
    {"version":1,"packs":[{"key":"acme","displayName":"Acme emojis","emoji":[\
    {"shortcode":"parrot","url":"mxc:\\/\\/example.org\\/parrot"},\
    {"shortcode":"shipit","url":"mxc:\\/\\/example.org\\/shipit"}]}]}
    """

    @Test func aCacheFileOfTheFirstFormatStillLoads() async throws {
        let backend = try makeBackend(cache: true)
        let directory = try #require(backend.cacheDirectory)
        try Data(Self.versionOneFile.utf8).write(to: ImagePackStore.cacheFile(for: Self.space.id, in: directory))
        backend.states[Self.space.id] = .failure(PackStoreReadFailed())
        let store = makeStore(PackStoreClock())

        await store.load(roomId: Self.room, from: backend.source)

        #expect(store.packs(forRoom: Self.room) == [
            ImagePack(key: "acme", displayName: "Acme emojis", emoji: [Self.emoji("parrot"), Self.emoji("shipit")]),
        ])
        #expect(store.learnedBySpace.isEmpty)

        // The first learned emoji writes the file in the new format.
        store.learn([Self.emoji("zebra")], roomId: Self.room)
        await store.waitForCacheWrites()
        let file = try JSONDecoder().decode(StoredFile.self, from: Data(cacheText(backend).utf8))
        #expect(file.version == 2)
        #expect(file.packs.first?.emoji.count == 2)
        #expect(file.learned == [Self.emoji("zebra")])
        removeCache(backend)
    }

    /// The shape that the store of MATRIX-155 decodes.
    private struct VersionOneFile: Decodable {
        let version: Int
        let packs: [ImagePack]
    }

    @Test func aBuildWithTheFirstFormatReadsTheNewFile() async throws {
        let backend = try makeBackend(cache: true)
        let store = makeStore(PackStoreClock())
        await store.load(roomId: Self.room, from: backend.source)
        store.learn([Self.emoji("zebra")], roomId: Self.room)
        await store.waitForCacheWrites()

        let file = try JSONDecoder().decode(VersionOneFile.self, from: Data(cacheText(backend).utf8))
        #expect(file.packs.first?.emoji.map(\.shortcode) == ["parrot", "shipit"])
        removeCache(backend)
    }
}
