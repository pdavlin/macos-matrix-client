import Foundation
import Models

/// The message types the row-kind switch distinguishes.
///
/// The real enum carries payloads; only the discriminant reaches the container,
/// through `MsgLikeContent.rowKind`, so the shim carries the discriminant.
public enum MessageType: String, Sendable, CaseIterable {
    case text
    case notice
    case emote
    case image
    case video
    case gallery
    case audio
    case file
    case location
    case other
}

public struct MessageContent: Sendable, Equatable {
    public var msgType: MessageType
    public var body: String

    public init(msgType: MessageType, body: String) {
        self.msgType = msgType
        self.body = body
    }
}

/// Shape of a message-like item.
public enum MsgLikeKind: Sendable, Equatable {
    case message(content: MessageContent)
    case sticker
    case poll
    case redacted
    case unableToDecrypt
    case liveLocation
    case other
}

/// One aggregated reaction on an event.
public struct ReactionSender: ReactionSenderData, Sendable {
    public let senderId: String
    public let date: Date

    public init(senderId: String, date: Date) {
        self.senderId = senderId
        self.date = date
    }
}

public struct Reaction: Models.Reaction, Sendable {
    public typealias SenderData = ReactionSender

    public let key: String
    public let senders: [ReactionSender]

    public init(key: String, senders: [ReactionSender]) {
        self.key = key
        self.senders = senders
    }

    public var id: String { key }
}

/// Message-like content: what a `.msgLike` event carries.
public struct MsgLikeContent: Sendable {
    public var kind: MsgLikeKind
    public var reactions: [Reaction]

    public init(kind: MsgLikeKind, reactions: [Reaction]) {
        self.kind = kind
        self.reactions = reactions
    }
}

/// An event's content. The container switches on `.msgLike` and falls through
/// to a state row for everything else.
public enum TimelineItemContent: Sendable, CustomStringConvertible {
    case msgLike(content: MsgLikeContent)
    case state(name: String)

    public var description: String {
        switch self {
        case .msgLike:
            return "message"
        case let .state(name):
            return name
        }
    }
}
