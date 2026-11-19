import Foundation
import MatrixRustSDK
import Models
import OSLog

// MATRIX-203: a Matrix link in a message body opens in the app. The SDK
// parses the link and answers the questions about the account; the rules
// are `Models.MatrixLinkPlan`.

public extension MatrixLink {
    /// The SDK's parse of a link (`parseMatrixEntityFrom(uri:)`): a
    /// matrix.to link or a `matrix:` URI. Nil for any other link.
    init?(url: URL) {
        guard let entity = parseMatrixEntityFrom(uri: url.absoluteString) else { return nil }
        self.init(entity: entity)
    }

    init(entity: MatrixEntity) {
        switch entity.id {
        case let .room(id):
            self = .room(.id(id), eventId: nil, via: entity.via)
        case let .roomAlias(alias):
            self = .room(.alias(alias), eventId: nil, via: entity.via)
        case let .eventOnRoomId(roomId, eventId):
            self = .room(.id(roomId), eventId: eventId, via: entity.via)
        case let .eventOnRoomAlias(alias, eventId):
            self = .room(.alias(alias), eventId: eventId, via: entity.via)
        case let .user(id):
            self = .user(id: id)
        }
    }
}

public extension MatrixClient {
    /// What the account knows about `link`, from the SDK: the alias's room
    /// (`resolveRoomAlias`), the membership, the event's thread
    /// (`loadOrFetchEvent`), and the DM with a user (`getDmRoom`, as the
    /// New Chat screen finds it). A failed call counts as "not known".
    func matrixLinkFacts(_ link: MatrixLink) async -> MatrixLinkFacts {
        switch link {
        case let .user(userId):
            let directRoomId: String?
            do {
                directRoomId = try client.getDmRoom(userId: userId)?.id
            } catch {
                Logger.matrixClient.error("matrix link: DM lookup failed: \(String(describing: error), privacy: .public)")
                directRoomId = nil
            }
            return MatrixLinkFacts(directRoomId: directRoomId)
        case let .room(address, eventId, _):
            guard let roomId = await roomId(of: address) else { return MatrixLinkFacts() }
            guard let room = try? client.getRoom(roomId: roomId), room.membership() == .joined else {
                return MatrixLinkFacts(roomId: roomId)
            }
            var threadRootId: String?
            if let eventId {
                do {
                    threadRootId = try await room.loadOrFetchEvent(eventId: eventId).threadRootEventId()
                } catch {
                    Logger.matrixClient.info("matrix link: event not loaded: \(String(describing: error), privacy: .public)")
                }
            }
            return MatrixLinkFacts(roomId: roomId, isJoined: true, threadRootId: threadRootId)
        }
    }

    private func roomId(of address: MatrixRoomAddress) async -> String? {
        switch address {
        case let .id(roomId):
            return roomId
        case let .alias(alias):
            do {
                return try await client.resolveRoomAlias(roomAlias: alias)?.roomId
            } catch {
                Logger.matrixClient.info("matrix link: alias did not resolve: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    /// Opens a Matrix link in `windowState` (MATRIX-203): the chat, with
    /// the event, or the New Chat screen prefilled. See `MatrixLinkPlan`.
    ///
    /// - Parameters:
    ///   - link: the SDK's parse of the link.
    ///   - url: the clicked link, for the New Chat join field.
    func openMatrixLink(_ link: MatrixLink, url: URL, in windowState: WindowState) async {
        let facts = await matrixLinkFacts(link)
        // A room window keeps its room: it never shows a merged chat
        // (MATRIX-116), and it gets only links to its own room.
        let document = windowState.isSingleRoomWindow ? MergedChatDocument() : mergedChats?.document ?? MergedChatDocument()
        let plan = MatrixLinkPlan.make(link: link, address: url.absoluteString, facts: facts, document: document)
        Logger.matrixClient.info("matrix link: \(String(describing: plan), privacy: .private)")
        switch plan {
        case let .open(selection, focus):
            windowState.pendingEventFocus = focus
            windowState.open(selection, from: .link)
        case let .newChat(mode, .person(person)):
            // The To: field shows the person's name and avatar when the
            // profile loads, else the user ID.
            let loaded = try? await newChatProfile(userId: person.userId)
            let profile = loaded ?? person
            windowState.pendingEventFocus = nil
            windowState.selectedScreen = .newChat(mode: mode, prefill: .person(profile))
        case let .newChat(mode, prefill):
            windowState.pendingEventFocus = nil
            windowState.selectedScreen = .newChat(mode: mode, prefill: prefill)
        }
    }
}
