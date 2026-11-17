import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The SDK and network side of the own profile image per service
/// (MATRIX-165): in a chat of a Slack workspace, an own message shows the
/// user's Slack image of that workspace.
///
/// The rules live in `Models` (`OwnServiceAvatarStore`, `BridgeInfo`,
/// `OwnServiceGhost`), where they are unit-tested. This file gives the store
/// its sources:
/// - the parent spaces and the candidate chats, from the SDK;
/// - the state of one direct chat per workspace, through the same
///   `RoomStateReader` and `RoomStateTransport` that the image packs use
///   (contract §11, row of 2026-11-16, decision b);
/// - the ghost's profile, through the SDK's `getProfile(userId:)`.
///
/// Nothing here writes, sends a message, or calls the bridge.
public extension MatrixClient {
    /// Loads the own image for the workspace of the room into
    /// `ownServiceAvatars` and returns at once. `loadImagePacks(forRoom:)`
    /// calls it, so a chat open is the trigger; a merged chat calls it for
    /// each member room. The store reads only when its answer is absent or
    /// old. Does nothing after a sign-out.
    ///
    /// - Parameter roomId: The room of the chat. In a merged chat, a member
    ///   room.
    func loadOwnServiceAvatar(forRoom roomId: String) {
        guard let source = ownServiceAvatarSource else { return }
        Task { await ownServiceAvatars.load(roomId: roomId, from: source) }
    }

    /// Where the store reads from, or nil after a sign-out.
    private var ownServiceAvatarSource: OwnServiceAvatarStore.Source? {
        guard let spaceService, let sdkClient: ClientProtocol = client,
              let accountUserId = try? sdkClient.userId()
        else { return nil }
        let service: SpaceService = spaceService.spaceService
        return OwnServiceAvatarStore.Source(
            cacheDirectory: URL.sessionCaches(for: storeID).appending(component: "OwnServiceProfiles"),
            accountUserId: accountUserId,
            parentSpaces: { [roomAccounts] roomId in
                let live = try await service.joinedParentsOfChild(childId: roomId).map(\.roomId)
                // MATRIX-170: the cached parents, until the SDK's space
                // graph is ready.
                return live.isEmpty ? roomAccounts.launchParents(of: roomId).map(\.id) : live
            },
            candidates: { [weak self] spaceId, excluding, limit in
                await self?.ownServiceCandidates(
                    inSpace: spaceId,
                    excluding: excluding,
                    limit: limit,
                    service: service,
                    accountUserId: accountUserId
                ) ?? []
            },
            fetchState: { roomId in
                try await RoomStateTransport.state(of: roomId, client: sdkClient)
            },
            fetchAvatarUrl: { userId in
                do {
                    return try await sdkClient.getProfile(userId: userId).avatarUrl
                } catch ClientError.MatrixApi(kind: .notFound, code: _, msg: _, details: _) {
                    // MATRIX-171: the ghost is gone, so the store reads the
                    // receiver of the workspace again.
                    throw OwnServiceAvatarStore.ProfileNotFound()
                }
            },
            report: { line in
                Logger.matrixClient.error("own service profile: \(line, privacy: .public)")
            }
        )
    }

    /// The direct chats of a space that can tell the own ghost: a direct
    /// room with a peer that is not a bot, whose parent space is `spaceId`.
    ///
    /// MATRIX-171: the rooms come from the unfiltered room list of the Dock
    /// badge tracker, not from the sidebar's `rooms`, which holds the rooms
    /// of the window's filter only. `OwnServiceCandidateRooms` holds the
    /// rule, with the sidebar's list as the fallback. Both lists are in the
    /// SDK's recency order, so the most recently active chat comes first.
    ///
    /// Cost: two SDK calls (`roomInfo`, `joinedParentsOfChild`) per direct
    /// room it looks at, and no request. The store limits how often it asks.
    private func ownServiceCandidates(
        inSpace spaceId: String,
        excluding: Set<String>,
        limit: Int,
        service: SpaceService,
        accountUserId: String
    ) async -> [OwnServiceAvatarStore.Candidate] {
        let account = dockBadge.unreadChats.listedRooms
        let sidebar = rooms.map { (room: $0.room, isDirect: $0.roomInfo?.isDirect) }
        var sdkRooms: [String: MatrixRustSDK.Room] = [:]
        let entries = [account, sidebar].map { list in
            list.map { entry in
                let id = entry.room.id()
                sdkRooms[id] = entry.room
                return OwnServiceCandidateRooms.Room(id: id, isDirect: entry.isDirect)
            }
        }
        let roomIds = OwnServiceCandidateRooms.roomIds(account: entries[0], sidebar: entries[1], excluding: excluding)

        var found: [OwnServiceAvatarStore.Candidate] = []
        for roomId in roomIds {
            guard found.count < limit else { break }
            guard let room = sdkRooms[roomId], let info = try? await room.roomInfo(), info.isDirect else { continue }
            let peers = OwnServiceGhost.peers(
                among: info.heroes.map(\.userId),
                serviceMembers: info.serviceMembers,
                accountUserId: accountUserId
            )
            guard !peers.isEmpty,
                  let parents = try? await service.joinedParentsOfChild(childId: roomId),
                  parents.contains(where: { $0.roomId == spaceId })
            else { continue }
            found.append(OwnServiceAvatarStore.Candidate(roomId: roomId, peerUserIds: peers))
        }
        return found
    }
}
