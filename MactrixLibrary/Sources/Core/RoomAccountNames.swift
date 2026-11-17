import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The names of the joined spaces that hold a room (MATRIX-147), read once
/// per room for the app session.
///
/// A bridge puts each chat of an account in that account's space (a Slack
/// workspace), so the space's name tells two chats with one person apart
/// (`MergedMemberIdentity`). Presentation only: the names come from the SDK's
/// space service, and nothing groups or routes on them.
///
/// MATRIX-170: the values start from the launch cache (`SpaceLaunchCache`),
/// so they are right in the first frame after a launch. `SpaceGraph` holds
/// the rule that says when a live answer replaces a cached value: an empty
/// answer does not erase a cached value before the SDK's space graph is
/// ready. Each change is written back to the cache file, at most one write
/// per `cacheWriteDelay`.
@MainActor @Observable
public final class RoomAccountNames {
    /// The parent space names by room ID. A room that was read and is in no
    /// joined space has an empty list.
    public private(set) var names: [String: [String]] = [:]

    /// The parent spaces by room ID, with their icons (MATRIX-148). Set with
    /// `names`, once per batch of reads, so a view that draws every room
    /// updates once per batch.
    public private(set) var spaces: [String: [ChatAccount]] = [:]

    /// The room IDs of the direct joined parent spaces, by child room ID
    /// (MATRIX-167). Set with `spaces`. A child is a room that was requested,
    /// or a parent space of one: the parents of each parent space are read
    /// too, so a chat in a nested sub-space maps to the top-level space
    /// (`RoomSpaceMap`).
    public private(set) var parentIds: [String: [String]] = [:]

    /// The top-level joined spaces, in the SDK's order (MATRIX-170): the
    /// cached list at launch, then the list of `LiveSpaceService.spaceRooms`.
    /// The rail reads this list, so its space items are there in the first
    /// frame.
    public private(set) var topLevelSpaces: [KnownSpace] = []

    /// The chats the launch cache knows, until the SDK's space graph is
    /// ready (MATRIX-170): see `SpaceGraph.launchChatIds`.
    public private(set) var launchChatIds: Set<String> = []

    /// Which spaces hold which rooms, for the rail's space filter.
    public var spaceMap: RoomSpaceMap {
        RoomSpaceMap(parents: parentIds)
    }

    /// The account of a room: see `ChatAccount.choose(from:network:)`.
    public func account(of roomId: String, network: ChatListNetwork?) -> ChatAccount? {
        guard let parents = spaces[roomId], !parents.isEmpty else { return nil }
        return ChatAccount.choose(from: parents, network: network)
    }

    /// The waits before the rooms with no parent space are read again. The
    /// SDK builds its space graph some time after the launch, and a read
    /// before that finds no parent for any room.
    static let retryDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32)]

    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private var pending: [String] = []
    /// The rooms whose last read found no parent space.
    @ObservationIgnored private var unplaced: Set<String> = []
    @ObservationIgnored private var retryRound = 0
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var observesSpaces = false

    /// The wait between a change and its write to the cache file. The
    /// changes in that time go into one write.
    static let cacheWriteDelay: Duration = .seconds(2)

    @ObservationIgnored private var graph = SpaceGraph()
    @ObservationIgnored private var cacheFile: URL?
    @ObservationIgnored private var cacheWrite: Task<Void, Never>?
    @ObservationIgnored private var cacheIsDirty = false
    @ObservationIgnored private var isStopped = false
    @ObservationIgnored private var syncEvidence = SessionSyncEvidence()
    /// Weak: `MatrixClient` owns the space service.
    @ObservationIgnored private weak var liveSpaces: LiveSpaceService?

    public init() {}

    /// Loads the launch cache (MATRIX-170). Call this one time at client
    /// start, before a view reads the values. The read is synchronous: the
    /// file is small, and the first frame needs the data.
    ///
    /// - Parameter cacheFile: `SpaceLaunchCache.file(in:)` of the session's
    ///   cache folder. Later changes are written to this file.
    public func restore(cacheFile: URL) {
        self.cacheFile = cacheFile
        graph = SpaceGraph(cache: SpaceLaunchCache.read(at: cacheFile))
        publish()
    }

    /// Follows the client's list of joined spaces from the client start, so
    /// the live list replaces the cached list also before the first
    /// `request`.
    public func attach(spaces: LiveSpaceService) {
        liveSpaces = spaces
        observeSpaces(spaces)
        applyTopLevel(of: spaces)
    }

    /// Takes a state of the room list service (MATRIX-171). The first state
    /// that shows a sync (`SessionSyncEvidence`: `running`) starts the
    /// retry rounds again: the SDK builds its space graph after the sync.
    public func note(roomListState: SessionSyncEvidence.RoomListState) {
        guard syncEvidence.note(roomListState), let liveSpaces else { return }
        retryRound = 0
        pending.append(contentsOf: unplaced.subtracting(pending))
        startWorker(spaceService: liveSpaces.spaceService)
    }

    /// Stops the reads and the cache writes, and waits for a write that is
    /// in progress. Call this at sign-out before the session's cache folder
    /// is removed, so a late write does not put the file back.
    public func stop() async {
        isStopped = true
        worker?.cancel()
        let write = cacheWrite
        write?.cancel()
        await write?.value
    }

    /// The cached parent spaces of a room while the SDK's space graph is
    /// not ready, for a reader that got "no parent" from the SDK (the image
    /// pack and the own service avatar lookups). Empty when the graph is
    /// ready: the SDK's answer is the truth then.
    public func launchParents(of roomId: String) -> [KnownSpace] {
        graph.isReady ? [] : graph.parents[roomId] ?? []
    }

    /// Queues the rooms that were not read yet and returns at once. One
    /// task reads the queue, so a view that goes away does not stop a read.
    ///
    /// A room with a parent space is read once. A room with none is read
    /// again after each of `retryDelays`, and again when the joined spaces
    /// change or the room is requested again, because "no parent" is also
    /// what the SDK answers before its space graph is ready. A read that
    /// fails is logged and runs again on the next request.
    ///
    /// MATRIX-186: when the retry rounds end after a sync and the SDK gave
    /// no space, the cached values stay and the cache file counts an empty
    /// session (`SpaceGraph.finishRetries(hasSynced:)`). Some empty sessions
    /// in a row clear the cache of an account with no space. MATRIX-171:
    /// with no sync the rounds end with no change, and
    /// `note(roomListState:)` starts them again when the sync comes.
    ///
    /// Cost: one SDK call per read.
    ///
    /// - Parameters:
    ///   - roomIds: the rooms.
    ///   - spaces: the client's space service.
    public func request(_ roomIds: [String], spaces: LiveSpaceService) {
        liveSpaces = spaces
        observeSpaces(spaces)
        var isNewInterest = false
        for roomId in roomIds {
            if requested.insert(roomId).inserted {
                pending.append(roomId)
                isNewInterest = true
            } else if unplaced.contains(roomId) {
                isNewInterest = true
            }
        }
        if isNewInterest {
            retryRound = 0
        }
        startWorker(spaceService: spaces.spaceService)
    }

    private func startWorker(spaceService: SpaceService) {
        guard !isStopped, worker == nil, !pending.isEmpty || !unplaced.isEmpty || graph.holdsCachedData else { return }
        worker = Task { [weak self] in
            while let self, !self.isStopped {
                await drain(spaceService: spaceService)
                guard !unplaced.isEmpty || graph.holdsCachedData else { break }
                guard retryRound < Self.retryDelays.count else {
                    var settled = graph
                    settled.finishRetries(hasSynced: syncEvidence.hasSynced)
                    apply(settled)
                    break
                }
                let delay = Self.retryDelays[retryRound]
                retryRound += 1
                try? await Task.sleep(for: delay)
                pending.append(contentsOf: unplaced.subtracting(pending))
            }
            self?.worker = nil
        }
    }

    private func drain(spaceService: SpaceService) async {
        var read = 0
        var found = 0
        // The answers of the batch. They go into the graph in one step
        // after the last read: the graph can change during a read (the list
        // of joined spaces), and the views update once per batch.
        var answers: [(roomId: String, parents: [KnownSpace])] = []
        defer {
            var newGraph = graph
            for answer in answers {
                newGraph.setParents(answer.parents, of: answer.roomId)
            }
            apply(newGraph)
        }
        while !isStopped, let roomId = pending.first {
            pending.removeFirst()
            do {
                let parentRooms = try await spaceService.joinedParentsOfChild(childId: roomId)
                let parents = parentRooms.map { KnownSpace(id: $0.roomId, name: $0.displayName, avatarUrl: $0.avatarUrl) }
                answers.append((roomId, parents))
                // MATRIX-167: read the parents of each parent space too.
                for parent in parentRooms where requested.insert(parent.roomId).inserted {
                    pending.append(parent.roomId)
                }
                if parents.isEmpty {
                    unplaced.insert(roomId)
                } else {
                    unplaced.remove(roomId)
                    found += 1
                }
                read += 1
            } catch {
                requested.remove(roomId)
                Logger.mergedChats.error(
                    "failed to read the parent spaces of \(roomId, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
        if read > 0 {
            Logger.mergedChats.info("read the parent spaces of \(read) room(s); \(found) in a space")
        }
    }

    /// Reads the unplaced rooms again when the joined spaces change.
    private func observeSpaces(_ spaces: LiveSpaceService) {
        guard !observesSpaces else { return }
        observesSpaces = true
        withObservationTracking {
            _ = spaces.spaceRooms
        } onChange: { [weak self, weak spaces] in
            Task { @MainActor [weak self, weak spaces] in
                guard let self, let spaces else { return }
                observesSpaces = false
                observeSpaces(spaces)
                applyTopLevel(of: spaces)
                retryRound = 0
                pending.append(contentsOf: unplaced.subtracting(pending))
                startWorker(spaceService: spaces.spaceService)
            }
        }
    }
}

// MARK: - The space graph and its cache file (MATRIX-170)

private extension RoomAccountNames {
    func applyTopLevel(of spaces: LiveSpaceService) {
        var newGraph = graph
        newGraph.setTopLevel(spaces.spaceRooms.map { space in
            KnownSpace(id: space.id, name: space.spaceRoom.displayName, avatarUrl: space.spaceRoom.avatarUrl)
        })
        apply(newGraph)
    }

    /// Takes a new graph: updates the values the views read, and starts a
    /// cache write.
    func apply(_ newGraph: SpaceGraph) {
        guard newGraph != graph else { return }
        graph = newGraph
        publish()
        scheduleCacheWrite()
    }

    /// Sets each observable value that changed, so a view updates only for
    /// a change.
    func publish() {
        let newSpaces = graph.parents.mapValues { list in
            list.map { ChatAccount(name: $0.name, avatarUrl: $0.avatarUrl) }
        }
        let newParentIds = graph.parents.mapValues { $0.map(\.id) }
        if newSpaces != spaces {
            names = newSpaces.mapValues { $0.map(\.name) }
            spaces = newSpaces
        }
        if newParentIds != parentIds {
            parentIds = newParentIds
        }
        if graph.topLevel != topLevelSpaces {
            topLevelSpaces = graph.topLevel
        }
        let newLaunchChatIds = graph.launchChatIds
        if newLaunchChatIds != launchChatIds {
            launchChatIds = newLaunchChatIds
        }
    }

    /// Writes the cache file after `cacheWriteDelay`. One task does the
    /// writes, so the changes of a batch of rooms go into one write and the
    /// file ends with the newest data.
    func scheduleCacheWrite() {
        guard let cacheFile, !isStopped else { return }
        cacheIsDirty = true
        guard cacheWrite == nil else { return }
        cacheWrite = Task {
            try? await Task.sleep(for: Self.cacheWriteDelay)
            while cacheIsDirty, !isStopped {
                cacheIsDirty = false
                if let problem = await SpaceLaunchCache.write(graph.cache, to: cacheFile) {
                    Logger.mergedChats.error("failed to write the space launch cache: \(problem, privacy: .public)")
                }
            }
            cacheWrite = nil
        }
    }
}

public extension MatrixClient {
    /// Reads the parent spaces of `roomIds` into `roomAccounts`. Does nothing
    /// after a sign-out.
    func loadRoomAccounts(_ roomIds: [String]) {
        guard let spaceService else { return }
        roomAccounts.request(roomIds, spaces: spaceService)
    }
}

public extension SidebarRoom {
    /// What tells this room from the other members of its merged chat.
    ///
    /// - Parameter accounts: the client's `roomAccounts`. The read is
    ///   observable, so a view shows the account when it loads.
    func mergedMemberIdentity(accounts: RoomAccountNames?) -> MergedMemberIdentity {
        MergedMemberIdentity(
            network: chatListPeople.network ?? ChatListNetwork.detect(heroUserIds: roomInfo?.serviceMembers ?? []),
            parentNames: accounts?.names[id] ?? [],
            peerUserId: roomInfo?.heroes.first?.userId,
            roomName: room.displayName()
        )
    }
}
