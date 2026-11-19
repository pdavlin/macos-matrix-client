import Foundation
import MatrixRustSDK
import Models
import OSLog

// MATRIX-208: the Bookmarks list reads each row's room and message through
// the SDK when it shows. The stored bookmark holds IDs only.

public extension MatrixClient {
    /// The room of a bookmark, from the SDK's room (`getRoom`): its name and
    /// avatar. Nil when the account does not have the room.
    func bookmarkRoom(roomId: String) -> BookmarkListRow.Room? {
        let room: MatrixRustSDK.Room?
        do {
            room = try client.getRoom(roomId: roomId)
        } catch {
            Logger.bookmarks.info("bookmark room lookup failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        guard let room else { return nil }
        let title = room.displayName() ?? roomId
        return BookmarkListRow.Room(
            title: title,
            avatarUrl: room.avatarUrl(),
            initials: .room(title: title, roomId: roomId)
        )
    }

    /// The bookmarked message, read with `loadOrFetchEvent`: the event cache,
    /// else the homeserver. Nil when the room or the event does not load.
    func bookmarkMessage(_ key: BookmarkKey) async -> BookmarkListRow.Message? {
        do {
            guard let room = try client.getRoom(roomId: key.roomId) else { return nil }
            let event = try await room.loadOrFetchEvent(eventId: key.eventId)
            let senderId = event.senderId()
            let senderName = try? await room.memberDisplayName(userId: senderId)
            let content: ChatListPreviewContent = (try? event.content()).map(\.bookmarkPreviewContent) ?? .other
            return BookmarkListRow.Message(
                senderName: senderName.flatMap { $0.isEmpty ? nil : $0 } ?? ChatListSender.localpart(of: senderId),
                preview: BookmarkListRow.preview(of: content, senderId: senderId, senderName: senderName),
                date: Date(timeIntervalSince1970: TimeInterval(event.timestamp()) / 1000)
            )
        } catch {
            Logger.bookmarks.info("bookmarked event did not load: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The link that opens a bookmark through the MATRIX-203 path: the
    /// room, scrolled to the event, which flashes. The URL is the SDK's
    /// permalink; `MatrixLinkPlan` uses it only for a room the account has
    /// not joined.
    func bookmarkLink(_ key: BookmarkKey) async -> (link: MatrixLink, url: URL) {
        let link = MatrixLink.room(.id(key.roomId), eventId: key.eventId, via: [])
        var permalink: String?
        if let room = try? client.getRoom(roomId: key.roomId) {
            permalink = try? await room.matrixToEventPermalink(eventId: key.eventId)
        }
        let url = permalink.flatMap(URL.init(string:)) ?? URL(string: "https://matrix.to/")
        // `URL(string:)` of a fixed literal never fails.
        return (link, url ?? URL(fileURLWithPath: "/"))
    }
}

extension MatrixRustSDK.TimelineEventContent {
    /// The preview kind of a loaded event (MATRIX-208), in the chat list's
    /// terms. Exhaustive with no `default`, as `ChatList+SDK` is.
    var bookmarkPreviewContent: ChatListPreviewContent {
        switch self {
        case let .messageLike(content):
            switch content {
            case let .roomMessage(messageType, _):
                return messageType.chatListContent
            case let .poll(question):
                return .poll(question: question)
            case .sticker:
                return .sticker
            case .roomEncrypted:
                return .unableToDecrypt
            case .callAnswer, .callInvite, .rtcNotification, .callHangup, .callCandidates, .keyVerificationReady,
                 .keyVerificationStart, .keyVerificationCancel, .keyVerificationAccept, .keyVerificationKey,
                 .keyVerificationMac, .keyVerificationDone, .reactionContent, .roomRedaction:
                return .other
            }
        case .state:
            return .other
        }
    }
}
