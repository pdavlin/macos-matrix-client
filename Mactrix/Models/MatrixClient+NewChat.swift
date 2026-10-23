import Foundation
import MatrixRustSDK
import Models
import OSLog
import Utils

/// The SDK side of the New Chat screen (MATRIX-75).
///
/// Every protocol step is an SDK call: the directory search, the profile
/// lookup, the DM lookup, room creation, and the join. The decisions between
/// them live in `Models` (`NewChatStartPlan`) and `Utils`
/// (`MatrixJoinTarget`), where they are unit-tested.
extension MatrixClient {
    struct UnrecognizedRoomAddress: LocalizedError {
        let address: String

        var errorDescription: String? {
            "Not a room address or Matrix link: \(address)"
        }
    }

    /// The user directory search, limited to 20 results.
    func searchNewChatPeople(query: String) async throws -> [NewChatPerson] {
        let results = try await client.searchUsers(searchTerm: query, limit: 20)
        return results.results.map { NewChatPerson(userId: $0.userId, displayName: $0.displayName, avatarUrl: $0.avatarUrl) }
    }

    /// The profile for an exact user ID typed in the To: field.
    func newChatProfile(userId: String) async throws -> NewChatPerson {
        let profile = try await client.getProfile(userId: userId)
        return NewChatPerson(userId: profile.userId, displayName: profile.displayName, avatarUrl: profile.avatarUrl)
    }

    /// Up to `limit` people from direct-message rooms, in room-list order,
    /// for the To: field's empty state.
    ///
    /// A DM's first hero is the other member; the SDK leaves the own user
    /// out of the heroes.
    func recentDirectContacts(limit: Int) -> [NewChatPerson] {
        var seen = Set<String>()
        var contacts: [NewChatPerson] = []

        for room in rooms {
            guard contacts.count < limit else { break }
            guard let roomInfo = room.roomInfo, roomInfo.isDirect, let hero = roomInfo.heroes.first else { continue }
            guard seen.insert(hero.userId).inserted else { continue }
            contacts.append(NewChatPerson(userId: hero.userId, displayName: hero.displayName, avatarUrl: hero.avatarUrl))
        }

        return contacts
    }

    /// Opens the existing DM or creates the room for `request`, and returns
    /// the room ID.
    ///
    /// New DMs are encrypted. Before MATRIX-75 the profile view's "Send
    /// message" created them unencrypted; it now routes through here too.
    func startChat(_ request: NewChatStartRequest) async throws -> String {
        var existingDirectRoomId: String?
        if case let .direct(userId) = request {
            existingDirectRoomId = try client.getDmRoom(userId: userId)?.id
        }

        switch NewChatStartPlan.make(request: request, existingDirectRoomId: existingDirectRoomId) {
        case let .openRoom(roomId):
            Logger.matrixClient.info("new chat: opening existing DM \(roomId)")
            return roomId
        case let .createDirect(userId):
            let parameters = CreateRoomParameters(
                name: nil, isEncrypted: true, isDirect: true, visibility: .private,
                preset: .privateChat, invite: [userId]
            )
            let roomId = try await client.createRoom(request: parameters)
            Logger.matrixClient.info("new chat: created DM \(roomId)")
            return roomId
        case let .createGroup(name, userIds, isEncrypted):
            let parameters = CreateRoomParameters(
                name: name, isEncrypted: isEncrypted, isDirect: false, visibility: .private,
                preset: .privateChat, invite: userIds
            )
            let roomId = try await client.createRoom(request: parameters)
            Logger.matrixClient.info("new chat: created group \(roomId), encrypted: \(isEncrypted)")
            return roomId
        }
    }

    /// `startChat` for one person, for callers outside the New Chat screen
    /// (the profile view's "Send message").
    func startDirectChat(userId: String) async throws -> String {
        try await startChat(.direct(userId: userId))
    }

    /// Joins the room named by a typed alias, room ID, `matrix:` URI, or
    /// matrix.to link, and returns its room ID.
    func joinNewChatRoom(address: String) async throws -> String {
        guard let target = MatrixJoinTarget(parsing: address) else {
            throw UnrecognizedRoomAddress(address: address)
        }
        let room = try await client.joinRoomByIdOrAlias(roomIdOrAlias: target.roomIdOrAlias, serverNames: target.viaServers)
        Logger.matrixClient.info("new chat: joined \(room.id)")
        return room.id
    }
}
