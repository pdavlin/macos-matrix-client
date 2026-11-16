import Foundation
import Models
import Testing

struct OwnServiceReadFailed: Error {}

/// The stubs behind an `OwnServiceAvatarStore.Source`, with call counts and
/// a gate that holds a profile read open.
@MainActor
final class OwnServiceBackend {
    var parents: [String: [String]] = [:]
    var chats: [String: [OwnServiceAvatarStore.Candidate]] = [:]
    var states: [String: Result<Data, Error>] = [:]
    var avatars: [String: Result<String?, Error>] = [:]
    var searches = 0
    var stateReads: [String] = []
    var profileReads: [String] = []
    var reports: [String] = []
    var holdsProfileReads = false
    var heldReads: [CheckedContinuation<Void, Never>] = []
    let cacheDirectory: URL?

    init(cacheDirectory: URL?) {
        self.cacheDirectory = cacheDirectory
    }

    var source: OwnServiceAvatarStore.Source {
        OwnServiceAvatarStore.Source(
            cacheDirectory: cacheDirectory,
            accountUserId: "@patrick:davlin.io",
            parentSpaces: { roomId in self.parents[roomId] ?? [] },
            candidates: { spaceId, excluding, limit in
                self.searches += 1
                return Array((self.chats[spaceId] ?? []).filter { !excluding.contains($0.roomId) }.prefix(limit))
            },
            fetchState: { roomId in
                self.stateReads.append(roomId)
                return try (self.states[roomId] ?? .failure(OwnServiceReadFailed())).get()
            },
            fetchAvatarUrl: { userId in
                self.profileReads.append(userId)
                if self.holdsProfileReads {
                    await withCheckedContinuation { self.heldReads.append($0) }
                }
                return try (self.avatars[userId] ?? .failure(OwnServiceReadFailed())).get()
            },
            report: { self.reports.append($0) }
        )
    }

    func releaseProfileReads() {
        holdsProfileReads = false
        for held in heldReads {
            held.resume()
        }
        heldReads = []
    }
}

/// What the store tests of MATRIX-165 share: the rooms, the space, and the
/// stubs.
@MainActor
protocol OwnServiceStoreFixture {}

extension OwnServiceStoreFixture {
    static var space: String { "!workspace:davlin.io" }
    static var channel: String { "!channel:davlin.io" }
    static var otherChannel: String { "!other-channel:davlin.io" }
    static var ghost: String { "@slack_t1c6g4l3c-u1ccdgwmd:davlin.io" }
    static var ghostAvatar: String { "mxc://davlin.io/own-slack" }

    static func chat(_ number: Int) -> OwnServiceAvatarStore.Candidate {
        OwnServiceAvatarStore.Candidate(roomId: "!dm\(number):davlin.io", peerUserIds: ["@slack_t1c6g4l3c-u000000\(number):davlin.io"])
    }

    static func bridgeState(receiver: String?) -> Data {
        let receiverField = receiver.map { ", \"fi.mau.receiver\": \"\($0)\"" } ?? ""
        return Data("""
        [{"type": "m.bridge", "state_key": "davlin.io/slack", "content": {"channel": {"id": "T1C6G4L3C-D01"\(receiverField)}}}]
        """.utf8)
    }

    func makeBackend(cache: Bool = false) throws -> OwnServiceBackend {
        var directory: URL?
        if cache {
            let url = FileManager.default.temporaryDirectory.appending(component: "OwnServiceAvatarStoreTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            directory = url
        }
        let backend = OwnServiceBackend(cacheDirectory: directory)
        backend.parents[Self.channel] = [Self.space]
        backend.parents[Self.otherChannel] = [Self.space]
        backend.chats[Self.space] = [Self.chat(1)]
        backend.states[Self.chat(1).roomId] = .success(Self.bridgeState(receiver: "T1C6G4L3C-U1CCDGWMD"))
        backend.avatars[Self.ghost] = .success(Self.ghostAvatar)
        return backend
    }

    func removeCache(_ backend: OwnServiceBackend) {
        if let directory = backend.cacheDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

/// MATRIX-165: the own service image by workspace. The clock and every
/// source are stubs: no SDK, no network.
@MainActor
struct OwnServiceAvatarStoreTests: OwnServiceStoreFixture {
    // MARK: - The two steps

    @Test func resolvesTheGhostFromOneChatAndReadsItsProfile() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })
        #expect(store.state(ofSpace: Self.space) == .unknown)
        #expect(store.avatarUrl(forRoom: Self.channel) == nil)

        await store.load(roomId: Self.channel, from: backend.source)

        #expect(backend.stateReads == [Self.chat(1).roomId])
        #expect(backend.profileReads == [Self.ghost])
        #expect(store.state(ofSpace: Self.space) == .resolved(avatarUrl: Self.ghostAvatar))
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)
        #expect(backend.reports.isEmpty)
    }

    @Test func aSecondRoomOfTheSpaceMakesNoRead() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        await store.load(roomId: Self.channel, from: backend.source)
        await store.load(roomId: Self.otherChannel, from: backend.source)
        await store.load(roomId: Self.channel, from: backend.source)

        #expect(backend.stateReads.count == 1)
        #expect(backend.profileReads.count == 1)
        #expect(store.avatarUrl(forRoom: Self.otherChannel) == Self.ghostAvatar)
    }

    @Test func aRoomWithNoParentSpaceReadsNothingAndAsksAgain() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })
        let room = "!later:davlin.io"

        await store.load(roomId: room, from: backend.source)
        #expect(backend.searches == 0)
        #expect(store.avatarUrl(forRoom: room) == nil)

        // The SDK's space graph is ready now.
        backend.parents[room] = [Self.space]
        await store.load(roomId: room, from: backend.source)
        #expect(store.avatarUrl(forRoom: room) == Self.ghostAvatar)
    }

    @Test func aProfileWithoutAvatarResolvesToNone() async throws {
        let backend = try makeBackend()
        backend.avatars[Self.ghost] = .success("")
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        await store.load(roomId: Self.channel, from: backend.source)

        #expect(store.state(ofSpace: Self.space) == .resolved(avatarUrl: nil))
        #expect(store.avatarUrl(forRoom: Self.channel) == nil)
    }

    @Test func oneLoadPerSpaceIsInFlight() async throws {
        let backend = try makeBackend()
        backend.holdsProfileReads = true
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        let first = Task { await store.load(roomId: Self.channel, from: backend.source) }
        while backend.heldReads.isEmpty {
            await Task.yield()
        }
        // Dropped: the first load holds the space.
        await store.load(roomId: Self.otherChannel, from: backend.source)
        #expect(backend.stateReads.count == 1)
        #expect(backend.profileReads.count == 1)

        backend.releaseProfileReads()
        await first.value
        #expect(store.avatarUrl(forRoom: Self.otherChannel) == Self.ghostAvatar)
    }

    // MARK: - Candidates

    @Test func triesTheNextChatWhenOneGivesNoGhost() async throws {
        let backend = try makeBackend()
        backend.chats[Self.space] = [
            OwnServiceAvatarStore.Candidate(roomId: "!dm1:davlin.io", peerUserIds: ["@slack_t1c6g4l3c-u0000001:davlin.io"]),
            OwnServiceAvatarStore.Candidate(roomId: "!dm2:davlin.io", peerUserIds: ["@slack_t9other-u0000002:davlin.io"]),
            OwnServiceAvatarStore.Candidate(roomId: "!dm3:davlin.io", peerUserIds: ["@slack_t1c6g4l3c-u0000003:davlin.io"]),
        ]
        backend.states["!dm1:davlin.io"] = .success(Self.bridgeState(receiver: nil))
        backend.states["!dm2:davlin.io"] = .success(Self.bridgeState(receiver: "T1C6G4L3C-U1CCDGWMD"))
        backend.states["!dm3:davlin.io"] = .success(Self.bridgeState(receiver: "T1C6G4L3C-U1CCDGWMD"))
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        await store.load(roomId: Self.channel, from: backend.source)

        #expect(backend.stateReads == ["!dm1:davlin.io", "!dm2:davlin.io", "!dm3:davlin.io"])
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)
    }

    @Test func readsAtMostThreeChatsPerSession() async throws {
        let backend = try makeBackend()
        backend.chats[Self.space] = (1 ... 6).map(Self.chat)
        for number in 1 ... 6 {
            backend.states[Self.chat(number).roomId] = .success(Self.bridgeState(receiver: nil))
        }
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.stateReads.count == OwnServiceAvatarStore.maxStateReads)
        #expect(store.state(ofSpace: Self.space) == .resolved(avatarUrl: nil))

        // "None" is the answer for the session: no later search, no read.
        clock.advance(by: OwnServiceAvatarStore.retryInterval * 10)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.stateReads.count == OwnServiceAvatarStore.maxStateReads)
        #expect(backend.searches == 1)
        #expect(backend.profileReads.isEmpty)
    }

    @Test func aSpaceWithNoChatResolvesToNoneAndSearchesAgainAfterTheInterval() async throws {
        let backend = try makeBackend()
        backend.chats[Self.space] = []
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        await store.load(roomId: Self.channel, from: backend.source)
        #expect(store.state(ofSpace: Self.space) == .resolved(avatarUrl: nil))
        #expect(backend.stateReads.isEmpty)

        clock.advance(by: OwnServiceAvatarStore.retryInterval - 1)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.searches == 1)

        // A direct chat showed in the chat list since.
        backend.chats[Self.space] = [Self.chat(1)]
        clock.advance(by: 1)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.searches == 2)
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)
    }

    @Test func emptySearchesStopAfterTheLimit() async throws {
        let backend = try makeBackend()
        backend.chats[Self.space] = []
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        for _ in 0 ..< OwnServiceAvatarStore.maxEmptySearches + 3 {
            await store.load(roomId: Self.channel, from: backend.source)
            clock.advance(by: OwnServiceAvatarStore.retryInterval)
        }
        #expect(backend.searches == OwnServiceAvatarStore.maxEmptySearches)
    }
}

/// MATRIX-165: failed reads, the profile interval, and the cache file.
@MainActor
struct OwnServiceAvatarStoreReadTests: OwnServiceStoreFixture {
    // MARK: - Failures

    @Test func aFailedStateReadWaitsThenReadsTheChatAgain() async throws {
        let backend = try makeBackend()
        let chatId = Self.chat(1).roomId
        backend.states[chatId] = .failure(RoomStateReader.Failure.status(502))
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        await store.load(roomId: Self.channel, from: backend.source)
        #expect(store.state(ofSpace: Self.space) == .failed)
        #expect(backend.reports == ["failed to read the bridge info for \(Self.space): status(502)"])

        clock.advance(by: OwnServiceAvatarStore.retryInterval - 1)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.stateReads.count == 1)

        backend.states[chatId] = .success(Self.bridgeState(receiver: "T1C6G4L3C-U1CCDGWMD"))
        clock.advance(by: 1)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.stateReads.count == 2)
        #expect(store.state(ofSpace: Self.space) == .resolved(avatarUrl: Self.ghostAvatar))
    }

    @Test func failedStateReadsCountInTheSessionLimit() async throws {
        let backend = try makeBackend()
        backend.states[Self.chat(1).roomId] = .failure(OwnServiceReadFailed())
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        for _ in 0 ..< 6 {
            await store.load(roomId: Self.channel, from: backend.source)
            clock.advance(by: OwnServiceAvatarStore.retryInterval)
        }
        #expect(backend.stateReads.count == OwnServiceAvatarStore.maxStateReads)
        #expect(store.state(ofSpace: Self.space) == .failed)
    }

    @Test func aFailedProfileReadKeepsTheGhostAndBacksOff() async throws {
        let backend = try makeBackend()
        backend.avatars[Self.ghost] = .failure(OwnServiceReadFailed())
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        for _ in 0 ..< OwnServiceAvatarStore.maxFailedReads + 2 {
            await store.load(roomId: Self.channel, from: backend.source)
        }
        // The state read ran once. The profile read stopped at the limit.
        #expect(backend.stateReads.count == 1)
        #expect(backend.profileReads.count == OwnServiceAvatarStore.maxFailedReads)
        #expect(store.state(ofSpace: Self.space) == .failed)

        backend.avatars[Self.ghost] = .success(Self.ghostAvatar)
        clock.advance(by: OwnServiceAvatarStore.retryInterval)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.stateReads.count == 1)
        #expect(store.state(ofSpace: Self.space) == .resolved(avatarUrl: Self.ghostAvatar))
    }

    // MARK: - The interval

    @Test func readsTheProfileAgainAfterADay() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })
        await store.load(roomId: Self.channel, from: backend.source)

        backend.avatars[Self.ghost] = .success("mxc://davlin.io/new-image")
        clock.advance(by: OwnServiceAvatarStore.profileRefreshInterval - 1)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.profileReads.count == 1)
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)

        clock.advance(by: 1)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.profileReads.count == 2)
        #expect(backend.stateReads.count == 1)
        #expect(store.avatarUrl(forRoom: Self.channel) == "mxc://davlin.io/new-image")
    }

    @Test func aFailedRefreshKeepsTheKnownImage() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })
        await store.load(roomId: Self.channel, from: backend.source)

        backend.avatars[Self.ghost] = .failure(OwnServiceReadFailed())
        clock.advance(by: OwnServiceAvatarStore.profileRefreshInterval)
        await store.load(roomId: Self.channel, from: backend.source)

        #expect(backend.profileReads.count == 2)
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)
    }

    // MARK: - The cache file

    @Test func theCacheGivesTheImageToANewSessionWithNoRead() async throws {
        let backend = try makeBackend(cache: true)
        defer { removeCache(backend) }
        let clock = PackStoreClock()
        let first = OwnServiceAvatarStore(now: { clock.time })
        await first.load(roomId: Self.channel, from: backend.source)
        await first.waitForCacheWrites()

        let directory = try #require(backend.cacheDirectory)
        let file = OwnServiceAvatarStore.cacheFile(for: Self.space, in: directory)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("T1C6G4L3C-U1CCDGWMD"))
        #expect(text.contains("slack_t1c6g4l3c-u1ccdgwmd"))
        #expect(text.contains("own-slack"))
        // The room state is not kept.
        #expect(!text.contains("m.bridge"))

        clock.advance(by: 60)
        let second = OwnServiceAvatarStore(now: { clock.time })
        await second.load(roomId: Self.channel, from: backend.source)
        #expect(second.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)
        #expect(backend.stateReads.count == 1)
        #expect(backend.profileReads.count == 1)
    }

    @Test func aNewSessionReadsOnlyTheProfileWhenTheCacheIsOld() async throws {
        let backend = try makeBackend(cache: true)
        defer { removeCache(backend) }
        let clock = PackStoreClock()
        let first = OwnServiceAvatarStore(now: { clock.time })
        await first.load(roomId: Self.channel, from: backend.source)
        await first.waitForCacheWrites()

        clock.advance(by: OwnServiceAvatarStore.profileRefreshInterval)
        backend.avatars[Self.ghost] = .success("mxc://davlin.io/new-image")
        let second = OwnServiceAvatarStore(now: { clock.time })
        await second.load(roomId: Self.channel, from: backend.source)

        #expect(backend.stateReads.count == 1)
        #expect(backend.profileReads.count == 2)
        #expect(second.avatarUrl(forRoom: Self.channel) == "mxc://davlin.io/new-image")
    }

    @Test func aCacheRecordForTheAccountItselfIsNotUsed() async throws {
        let backend = try makeBackend(cache: true)
        defer { removeCache(backend) }
        let directory = try #require(backend.cacheDirectory)
        let record = """
        {"version": 1, "record": {"receiver": "T1C6G4L3C-U1CCDGWMD", "ghostUserId": "@patrick:davlin.io", "avatarUrl": "mxc://davlin.io/x"}}
        """
        try Data(record.utf8).write(to: OwnServiceAvatarStore.cacheFile(for: Self.space, in: directory))
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })

        await store.load(roomId: Self.channel, from: backend.source)

        #expect(backend.stateReads.count == 1)
        #expect(backend.profileReads == [Self.ghost])
    }
}
