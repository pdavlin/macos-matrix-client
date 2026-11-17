import Foundation
@testable import Models
import Testing

/// MATRIX-186: the launch cache survives a short launch and a launch where
/// the SDK builds its space graph late. An empty answer clears the cache
/// only after some empty sessions in a row, each after a real sync.
struct SpaceLaunchCacheEmptySessionTests {
    private static let dev = KnownSpace(id: "!dev", name: "DevObsessed", avatarUrl: "mxc://a/dev")
    private static let pizza = KnownSpace(id: "!pizza", name: "pizza box audit committee")
    private static let sub = KnownSpace(id: "!sub", name: "Team")

    /// Two top-level spaces. `!deep` is in `!sub`, a sub-space of `!dev`.
    private static let cache = SpaceLaunchCache(
        topLevel: [dev, pizza],
        rooms: [
            "!d1": .init(parents: [dev]),
            "!p1": .init(parents: [pizza]),
            "!deep": .init(parents: [sub]),
            "!sub": .init(parents: [dev]),
        ]
    )

    private func railIds(of graph: SpaceGraph, liveChatIds: Set<String> = []) -> [String] {
        let joined = graph.topLevel.map { ChatListRailSpace(id: $0.id, name: $0.name, avatarUrl: $0.avatarUrl) }
        let map = RoomSpaceMap(parents: graph.parents.mapValues { $0.map(\.id) })
        return ChatListRailSpace.items(
            joined: joined,
            spaces: map,
            chatIds: liveChatIds.union(graph.launchChatIds),
            unread: [:]
        ).map(\.id)
    }

    // MARK: - The launch of the bug

    /// The sequence of the bug: the room list service goes to `settingUp`
    /// (and maybe `running`), the SDK answers "no space" through all the
    /// retry rounds, the rounds end, the app quits. The next launch has its
    /// spaces in the first frame.
    @Test(arguments: [
        [SessionSyncEvidence.RoomListState.initial, .settingUp],
        [.initial, .settingUp, .running],
    ])
    func aLateSpaceGraphKeepsTheCacheForTheNextLaunch(states: [SessionSyncEvidence.RoomListState]) {
        var evidence = SessionSyncEvidence()
        var graph = SpaceGraph(cache: Self.cache)
        for state in states {
            evidence.note(state)
        }
        // The first read and each of the five retry rounds: no space, no
        // parent.
        for _ in 0 ..< 6 {
            graph.setTopLevel([])
            for roomId in ["!d1", "!p1", "!deep", "!sub"] {
                graph.setParents([], of: roomId)
            }
        }
        graph.finishRetries(hasSynced: evidence.hasSynced)
        #expect(railIds(of: graph) == ["!dev", "!pizza"])

        // Quit: the file the session wrote.
        let saved = graph.cache
        #expect(saved.topLevel == Self.cache.topLevel)
        #expect(saved.rooms == Self.cache.rooms)
        #expect(saved.emptyLaunches == (evidence.hasSynced ? 1 : 0))

        // The next launch: the rail and a restored filter in the first
        // frame, before any live answer.
        var next = SpaceGraph(cache: saved)
        #expect(railIds(of: next) == ["!dev", "!pizza"])
        #expect(next.launchChatIds == ["!d1", "!p1", "!deep"])

        // The SDK gives its graph later in the launch.
        next.setTopLevel([Self.dev, Self.pizza])
        next.setParents([Self.dev], of: "!d1")
        #expect(next.isReady)
        #expect(next.cache.emptyLaunches == 0)
        #expect(railIds(of: next, liveChatIds: ["!d1", "!p1", "!deep"]) == ["!dev", "!pizza"])
    }

    /// A launch that synced and quits before the rounds end changes nothing.
    @Test func aShortLaunchKeepsTheFile() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setTopLevel([])
        graph.setParents([], of: "!d1")
        #expect(graph.cache == Self.cache)
    }

    // MARK: - Empty sessions

    @Test func retriesExhaustedAfterASyncWithNoSpaceKeepsTheCache() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setTopLevel([])
        for roomId in ["!d1", "!p1", "!deep", "!sub"] {
            graph.setParents([], of: roomId)
        }

        // The end of the rounds is not evidence. The session is an empty
        // session: the data stays, and the file counts it.
        graph.finishRetries(hasSynced: true)
        #expect(!graph.isReady)
        #expect(graph.holdsCachedData)
        #expect(graph.topLevel == [Self.dev, Self.pizza])
        #expect(graph.parents["!d1"] == [Self.dev])
        #expect(railIds(of: graph, liveChatIds: ["!d1", "!p1", "!deep"]) == ["!dev", "!pizza"])
        var expected = Self.cache
        expected.emptyLaunches = 1
        #expect(graph.cache == expected)

        // A second end of the rounds in the session counts one time.
        graph.finishRetries(hasSynced: true)
        #expect(graph.cache == expected)
    }

    @Test func anAccountWithNoSpaceClearsTheCacheAfterSomeEmptySessions() {
        var cache = Self.cache
        for launch in 1 ... SpaceLaunchCache.maxUnconfirmedLaunches {
            var graph = SpaceGraph(cache: cache)
            #expect(railIds(of: graph) == ["!dev", "!pizza"], "launch \(launch)")
            graph.setTopLevel([])
            graph.setParents([], of: "!d1")
            graph.finishRetries(hasSynced: true)
            cache = graph.cache
            #expect(cache.emptyLaunches == launch)
        }
        let graph = SpaceGraph(cache: cache)
        #expect(graph.topLevel.isEmpty)
        #expect(graph.parents.isEmpty)
        #expect(!graph.holdsCachedData)
        #expect(railIds(of: graph).isEmpty)
        #expect(graph.cache.isEmpty)
    }

    @Test func aSessionWithEvidenceResetsTheEmptyCount() {
        var cache = Self.cache
        cache.emptyLaunches = SpaceLaunchCache.maxUnconfirmedLaunches - 1
        var graph = SpaceGraph(cache: cache)
        #expect(railIds(of: graph) == ["!dev", "!pizza"])
        graph.setTopLevel([Self.dev, Self.pizza])
        #expect(graph.cache.emptyLaunches == 0)
    }

    @Test func aGraphThatComesAfterTheRoundsEndedIsTaken() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setParents([], of: "!p1")
        graph.finishRetries(hasSynced: true)
        #expect(graph.cache.emptyLaunches == 1)

        // The SDK built its graph late: the caller reads the rooms again.
        graph.setTopLevel([Self.dev])
        #expect(graph.isReady)
        #expect(graph.cache.emptyLaunches == 0)
        graph.setParents([Self.dev], of: "!d1")
        graph.finishRetries(hasSynced: true)
        #expect(graph.topLevel == [Self.dev])
        #expect(graph.parents["!d1"] == [Self.dev])
        // The held empty answer is real now.
        #expect(graph.parents["!p1"] == [])
    }

    @Test func aFileWithNoEmptyCountLoadsWithACountOfZero() {
        let json = """
        {"version": 1,
         "topLevel": [{"id": "!dev", "name": "DevObsessed", "avatarUrl": "mxc://a/dev"}],
         "rooms": {"!d1": {"parents": [{"id": "!dev", "name": "DevObsessed", "avatarUrl": "mxc://a/dev"}], "unconfirmedLaunches": 0}}}
        """
        let cache = SpaceLaunchCache.decode(Data(json.utf8))
        #expect(cache.emptyLaunches == 0)
        #expect(cache.topLevel == [Self.dev])
        #expect(railIds(of: SpaceGraph(cache: cache)) == ["!dev"])
    }

    // MARK: - No sync in this session (MATRIX-171)

    @Test func theSyncAfterAnOfflineStartCountsTheSessionOnly() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setParents([], of: "!p1")
        graph.finishRetries(hasSynced: false)
        #expect(graph.parents["!p1"] == [Self.pizza])
        #expect(graph.cache == Self.cache)

        // The network came back, and the SDK gave no space in the rounds
        // that follow the sync: an empty session, the data stays.
        graph.finishRetries(hasSynced: true)
        #expect(!graph.isReady)
        #expect(graph.parents["!p1"] == [Self.pizza])
        #expect(graph.topLevel == [Self.dev, Self.pizza])
        #expect(graph.cache.emptyLaunches == 1)
    }

    /// The full offline launch: the room list service never answers, the
    /// rounds end, the app quits, and the next launch has the same file.
    @Test func anOfflineLaunchKeepsTheFile() {
        var evidence = SessionSyncEvidence()
        var graph = SpaceGraph(cache: Self.cache)
        for state: SessionSyncEvidence.RoomListState in [.initial, .settingUp, .error, .recovering, .error] {
            evidence.note(state)
        }
        graph.setTopLevel([])
        for roomId in ["!d1", "!p1", "!deep", "!sub"] {
            graph.setParents([], of: roomId)
        }
        graph.finishRetries(hasSynced: evidence.hasSynced)

        let saved = graph.cache
        #expect(saved == Self.cache)
        #expect(railIds(of: SpaceGraph(cache: saved)) == ["!dev", "!pizza"])
    }
}
