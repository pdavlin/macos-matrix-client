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
@MainActor @Observable
public final class RoomAccountNames {
    /// The parent space names by room ID. A room that was read and is in no
    /// joined space has an empty list.
    public private(set) var names: [String: [String]] = [:]

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

    public init() {}

    /// Queues the rooms that were not read yet and returns at once. One
    /// task reads the queue, so a view that goes away does not stop a read.
    ///
    /// A room with a parent space is read once. A room with none is read
    /// again after each of `retryDelays`, and again when the joined spaces
    /// change or the room is requested again, because "no parent" is also
    /// what the SDK answers before its space graph is ready. A read that
    /// fails is logged and runs again on the next request.
    ///
    /// Cost: one SDK call per read.
    ///
    /// - Parameters:
    ///   - roomIds: the rooms.
    ///   - spaces: the client's space service.
    public func request(_ roomIds: [String], spaces: LiveSpaceService) {
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
        guard worker == nil, !pending.isEmpty || !unplaced.isEmpty else { return }
        worker = Task { [weak self] in
            while let self {
                await drain(spaceService: spaceService)
                guard !unplaced.isEmpty, retryRound < Self.retryDelays.count else { break }
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
        while let roomId = pending.first {
            pending.removeFirst()
            do {
                let parents = try await spaceService.joinedParentsOfChild(childId: roomId).map(\.displayName)
                if names[roomId] != parents {
                    names[roomId] = parents
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
                retryRound = 0
                pending.append(contentsOf: unplaced.subtracting(pending))
                startWorker(spaceService: spaces.spaceService)
            }
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
