import Foundation
@testable import Models
import Testing

/// MATRIX-170: the launch cache of the space data, and the rule that says
/// when a live answer replaces a cached value.
struct SpaceLaunchCacheTests {
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

    // MARK: - The file format

    @Test func encodesAndDecodesWithTheVersion() throws {
        let data = try Self.cache.encoded()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect(SpaceLaunchCache.decode(data) == Self.cache)
    }

    @Test func decodesTheDocumentedFormat() {
        let json = """
        {"version": 1,
         "topLevel": [{"id": "!dev", "name": "DevObsessed", "avatarUrl": "mxc://a/dev"}],
         "rooms": {"!d1": {"parents": [{"id": "!dev", "name": "DevObsessed"}], "unconfirmedLaunches": 2}}}
        """
        let cache = SpaceLaunchCache.decode(Data(json.utf8))
        #expect(cache.topLevel == [Self.dev])
        #expect(cache.rooms["!d1"] == .init(parents: [KnownSpace(id: "!dev", name: "DevObsessed")], unconfirmedLaunches: 2))
    }

    @Test(arguments: [
        "",
        "not json",
        "{\"version\": 1}",
        "{\"version\": 0, \"topLevel\": [{\"id\": \"!dev\", \"name\": \"Dev\"}], \"rooms\": {}}",
        "{\"version\": 2, \"topLevel\": [{\"id\": \"!dev\", \"name\": \"Dev\"}], \"rooms\": {}}",
    ])
    func anOldOrCorruptFileLoadsAsEmpty(json: String) {
        let cache = SpaceLaunchCache.decode(Data(json.utf8))
        #expect(cache.isEmpty)
        #expect(cache.version == SpaceLaunchCache.currentVersion)
    }

    @Test func readsAndWritesTheFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(component: "space-launch-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = SpaceLaunchCache.file(in: directory)
        #expect(file.lastPathComponent == "SpaceLaunchCache.json")

        #expect(SpaceLaunchCache.read(at: file).isEmpty)
        let problem = await SpaceLaunchCache.write(Self.cache, to: file)
        #expect(problem == nil)
        #expect(SpaceLaunchCache.read(at: file) == Self.cache)

        try Data("{".utf8).write(to: file)
        #expect(SpaceLaunchCache.read(at: file).isEmpty)
    }

    // MARK: - Cached data before a live answer

    @Test func cachedDataShowsBeforeAnyLiveAnswer() {
        let graph = SpaceGraph(cache: Self.cache)
        #expect(!graph.isReady)
        #expect(graph.holdsCachedData)
        #expect(graph.topLevel == [Self.dev, Self.pizza])
        #expect(graph.parents["!d1"] == [Self.dev])
        // The cached chats, without the sub-space.
        #expect(graph.launchChatIds == ["!d1", "!p1", "!deep"])
        // The rail has its items with no live room and no live space.
        #expect(railIds(of: graph) == ["!dev", "!pizza"])
        // A restored space filter applies at once, with its chats.
        let filter = ChatListRailFilter.space("!dev")
        #expect(filter.resolved(labels: ChatLabelDocument(), spaceIds: Set(railIds(of: graph))) == filter)
        let map = RoomSpaceMap(parents: graph.parents.mapValues { $0.map(\.id) })
        #expect(filter.narrowingRoomIds(labels: ChatLabelDocument(), spaces: map, chatIds: graph.launchChatIds) == ["!d1", "!deep"])
    }

    @Test func anEmptyCacheGivesAnEmptyGraph() {
        let graph = SpaceGraph()
        #expect(graph.topLevel.isEmpty)
        #expect(graph.parents.isEmpty)
        #expect(!graph.holdsCachedData)
        #expect(graph.launchChatIds.isEmpty)
        #expect(graph.cache.isEmpty)
    }

    // MARK: - Live answers

    @Test func aLiveNonEmptyAnswerReplacesTheCachedValue() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setParents([Self.pizza], of: "!d1")
        #expect(graph.isReady)
        #expect(graph.parents["!d1"] == [Self.pizza])
        // The other cached values stay until their own answer.
        #expect(graph.parents["!p1"] == [Self.pizza])
        #expect(graph.topLevel == [Self.dev, Self.pizza])

        let renamed = KnownSpace(id: "!dev", name: "Dev", avatarUrl: nil)
        graph.setTopLevel([Self.pizza, renamed])
        #expect(graph.topLevel == [Self.pizza, renamed])
    }

    @Test func anEarlyEmptyAnswerKeepsTheCache() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setTopLevel([])
        graph.setParents([], of: "!d1")
        graph.setParents([], of: "!sub")
        #expect(!graph.isReady)
        #expect(graph.topLevel == [Self.dev, Self.pizza])
        #expect(graph.parents["!d1"] == [Self.dev])
        #expect(graph.parents["!sub"] == [Self.dev])
        #expect(railIds(of: graph) == ["!dev", "!pizza"])
        #expect(graph.cache == Self.cache)
    }

    @Test func anEarlyEmptyAnswerForARoomWithNoCachedValueIsRecorded() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setParents([], of: "!new")
        #expect(!graph.isReady)
        #expect(graph.parents["!new"] == [])
    }

    @Test func anEmptyAnswerAfterTheGraphIsReadyClears() {
        var graph = SpaceGraph(cache: Self.cache)
        // Held: the graph is not ready.
        graph.setParents([], of: "!d1")
        // Evidence: the list of spaces is not empty.
        graph.setTopLevel([Self.dev, Self.pizza])
        #expect(graph.isReady)
        // The held answer is not applied by the evidence: the caller reads
        // the room again.
        #expect(graph.parents["!d1"] == [Self.dev])
        graph.setParents([], of: "!d1")
        #expect(graph.parents["!d1"] == [])
        #expect(graph.cache.rooms["!d1"] == nil)

        // An empty list of spaces is real too.
        graph.setTopLevel([])
        #expect(graph.topLevel.isEmpty)
    }

    @Test func aNonEmptyParentListOfOneRoomIsEvidenceToo() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setParents([Self.dev], of: "!d1")
        #expect(graph.isReady)
        graph.setParents([], of: "!p1")
        #expect(graph.parents["!p1"] == [])
        #expect(graph.launchChatIds.isEmpty)
    }

    // MARK: - The retry rounds end

    // MATRIX-186: the end of the rounds with no evidence is in
    // `SpaceLaunchCacheEmptySessionTests`.

    @Test func retriesExhaustedAfterEvidenceKeepsTheLiveData() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setParents([], of: "!p1")
        graph.setTopLevel([Self.dev])
        graph.setParents([Self.dev], of: "!d1")
        graph.finishRetries(hasSynced: true)
        #expect(graph.topLevel == [Self.dev])
        #expect(graph.parents["!d1"] == [Self.dev])
        // The held empty answer is real now.
        #expect(graph.parents["!p1"] == [])
        // A cached room that was not read keeps its value.
        #expect(graph.parents["!deep"] == [Self.sub])
    }

    // MARK: - No sync in this session (MATRIX-171)

    @Test func retriesExhaustedWithNoSyncKeepsTheCachedData() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setTopLevel([])
        for roomId in ["!d1", "!p1", "!deep", "!sub"] {
            graph.setParents([], of: roomId)
        }
        let before = graph

        graph.finishRetries(hasSynced: false)

        #expect(graph == before)
        #expect(!graph.isReady)
        #expect(graph.holdsCachedData)
        #expect(graph.topLevel == [Self.dev, Self.pizza])
        #expect(railIds(of: graph) == ["!dev", "!pizza"])
        // The file of the next launch is the file of this launch.
        #expect(graph.cache == Self.cache)
    }

    @Test func onlyAStateAfterASyncResponseIsEvidence() {
        let withSync = SessionSyncEvidence.RoomListState.allCases.filter(\.showsSync)
        #expect(withSync == [.running])
    }

    @Test func theSyncEvidenceIsALatch() {
        var evidence = SessionSyncEvidence()
        #expect(!evidence.hasSynced)
        // A start with no network, and the first request (MATRIX-186).
        for state: SessionSyncEvidence.RoomListState in [.initial, .settingUp, .error, .recovering, .terminated] {
            let isFirst = evidence.note(state)
            #expect(!isFirst)
        }
        #expect(!evidence.hasSynced)

        // The first evidence is reported one time.
        let first = evidence.note(.running)
        let second = evidence.note(.running)
        #expect(first)
        #expect(!second)
        // A later loss of the network does not clear it.
        evidence.note(.error)
        #expect(evidence.hasSynced)
    }

    // MARK: - Stale data

    @Test func aLeftSpaceDisappears() {
        var graph = SpaceGraph(cache: Self.cache)
        // The account left the pizza space: the live list does not hold it.
        graph.setTopLevel([Self.dev])
        #expect(railIds(of: graph, liveChatIds: ["!d1", "!p1"]) == ["!dev"])
        graph.setParents([], of: "!p1")
        graph.setParents([Self.dev], of: "!d1")

        let saved = graph.cache
        #expect(saved.topLevel == [Self.dev])
        #expect(saved.rooms["!p1"] == nil)
        let roomsInPizza = saved.rooms.filter { $0.value.parents.contains(Self.pizza) }
        #expect(roomsInPizza.isEmpty)

        let next = SpaceGraph(cache: saved)
        #expect(railIds(of: next) == ["!dev"])
    }

    @Test func aRoomWithNoLiveAnswerLeavesTheFileAfterSomeLaunches() {
        var cache = Self.cache
        for launch in 1 ... SpaceLaunchCache.maxUnconfirmedLaunches {
            var graph = SpaceGraph(cache: cache)
            #expect(graph.parents["!p1"] == [Self.pizza], "launch \(launch)")
            // A ready graph, and no answer for `!p1`: the account left it.
            graph.setTopLevel([Self.dev, Self.pizza])
            graph.setParents([Self.dev], of: "!d1")
            cache = graph.cache
            #expect(cache.rooms["!p1"]?.unconfirmedLaunches == launch)
            #expect(cache.rooms["!d1"]?.unconfirmedLaunches == 0)
        }
        let graph = SpaceGraph(cache: cache)
        #expect(graph.parents["!p1"] == nil)
        #expect(graph.cache.rooms["!p1"] == nil)
    }

    @Test func aSessionThatWasNeverReadyDoesNotAgeTheCache() {
        var graph = SpaceGraph(cache: Self.cache)
        graph.setParents([], of: "!d1")
        #expect(graph.cache == Self.cache)
    }
}
