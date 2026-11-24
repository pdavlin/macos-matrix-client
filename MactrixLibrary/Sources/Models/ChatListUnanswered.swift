import Foundation

/// One message, named by its sender and its server time (MATRIX-224).
///
/// The SDK's latest event (`LatestEventValue`) has no event ID, so the
/// Unanswered rule matches a timeline message to it by these two values.
public struct ChatListMessageKey: Codable, Equatable, Hashable, Sendable {
    /// The full Matrix user ID of the sender.
    public var senderId: String
    /// The message's `origin_server_ts`.
    public var timestamp: Date

    public init(senderId: String, timestamp: Date) {
        self.senderId = senderId
        self.timestamp = timestamp
    }
}

/// The Unanswered list filter's rule (MATRIX-224), Beeper's
/// `isUnresponded`: the chat's last message is from another person, and it
/// has no reaction from the user.
///
/// An app rule over the latest event, as the MATRIX-206 activity rule. The
/// SDK's latest event carries no reactions, so the caller gives the own
/// reaction it knows from a timeline (`ownReaction`).
///
/// Usage:
/// ```swift
/// ChatListUnanswered.isUnanswered(latest, ownReaction: nil) // true for a text from Alice
/// ```
public enum ChatListUnanswered {
    /// True when the chat waits for an answer from the user.
    ///
    /// - Parameters:
    ///   - latest: the chat's latest event, or nil when it has none.
    ///   - ownReaction: the latest message from another person that the
    ///     user reacted to, as far as the app knows, or nil.
    /// - Returns: true when `latest` is a message (`isMessage`) from another
    ///   person and `ownReaction` does not name it. An own message, a
    ///   deleted message, an invite, a membership change, and every other
    ///   event give false.
    public static func isUnanswered(_ latest: ChatListLatestEvent?, ownReaction: ChatListMessageKey?) -> Bool {
        guard let latest, !latest.sender.isOwn, latest.content.isMessage else { return false }
        return ownReaction != latest.messageKey
    }

    /// The own-reaction mark a room's timeline gives for its newest
    /// message: the message's key when another person sent it and the user
    /// reacted to it, else nil.
    ///
    /// - Parameters:
    ///   - message: the newest message of the room's main timeline.
    ///   - isOwn: the user sent the message.
    ///   - reactionSenderIds: the senders of every reaction on the message.
    ///   - ownUserId: the user's Matrix ID.
    public static func ownReactionMark(
        message: ChatListMessageKey,
        isOwn: Bool,
        reactionSenderIds: [String],
        ownUserId: String
    ) -> ChatListMessageKey? {
        guard !isOwn, reactionSenderIds.contains(ownUserId) else { return nil }
        return message
    }
}

public extension ChatListLatestEvent {
    /// The sender and time of this event.
    var messageKey: ChatListMessageKey {
        ChatListMessageKey(senderId: sender.userId, timestamp: timestamp)
    }
}

public extension ChatListPreviewContent {
    /// The event is a message a person can answer: text, an emote, media, a
    /// file, a sticker, a poll, a location, or a message that did not
    /// decrypt. A deleted message, an invite, a membership change, and the
    /// other events are not.
    var isMessage: Bool {
        switch self {
        case .text, .emote, .image, .video, .audio, .file, .gallery, .sticker, .poll, .location, .unableToDecrypt:
            true
        case .redacted, .invite, .membership, .other:
            false
        }
    }
}
