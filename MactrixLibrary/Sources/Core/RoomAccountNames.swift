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

    @ObservationIgnored private var requested: Set<String> = []

    public init() {}

    /// Reads the parent spaces of the rooms that were not read yet. A read
    /// that fails is logged and runs again on the next call.
    ///
    /// Cost: one SDK call per new room; nothing for a room read before.
    ///
    /// - Parameters:
    ///   - roomIds: the rooms.
    ///   - spaceService: the client's space service.
    public func load(_ roomIds: [String], spaceService: SpaceService) async {
        for roomId in roomIds where requested.insert(roomId).inserted {
            do {
                let parents = try await spaceService.joinedParentsOfChild(childId: roomId)
                names[roomId] = parents.map(\.displayName)
            } catch {
                requested.remove(roomId)
                Logger.mergedChats.error(
                    "failed to read the parent spaces of \(roomId, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}

public extension MatrixClient {
    /// Reads the parent spaces of `roomIds` into `roomAccounts`. Does nothing
    /// after a sign-out.
    func loadRoomAccounts(_ roomIds: [String]) async {
        guard let spaceService = spaceService?.spaceService else { return }
        await roomAccounts.load(roomIds, spaceService: spaceService)
    }
}

public extension SidebarRoom {
    /// What tells this room from the other members of its merged chat.
    ///
    /// - Parameter accounts: the client's `roomAccounts`. The read is
    ///   observable, so a view shows the account when it loads.
    func mergedMemberIdentity(accounts: RoomAccountNames?) -> MergedMemberIdentity {
        MergedMemberIdentity(
            network: chatListPeople.network,
            parentNames: accounts?.names[id] ?? [],
            peerUserId: roomInfo?.heroes.first?.userId,
            roomName: room.displayName()
        )
    }
}
