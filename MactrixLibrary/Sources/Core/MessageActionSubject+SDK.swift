import Foundation
import MatrixRustSDK
import Models

// MARK: - Message action subject (MATRIX-108)

public extension Models.MessageActionSubject {
    /// Builds the action model's input from an SDK timeline message.
    ///
    /// Every switch is exhaustive with no `default`, so a new SDK case has to
    /// be given a content kind here.
    ///
    /// - Parameters:
    ///   - event: The timeline event.
    ///   - msg: The event's message-like content.
    ///   - pinnedEventIds: The room's pinned event IDs, from `RoomInfo`.
    ///   - redactPermission: The room's redact permission, from
    ///     `LiveRoom.redactPermission` (MATRIX-110).
    init(
        event: MatrixRustSDK.EventTimelineItem,
        msg: MatrixRustSDK.MsgLikeContent,
        pinnedEventIds: [String],
        redactPermission: Models.MessageRedactPermission
    ) {
        var eventId: String?
        if case let .eventId(id) = event.eventOrTransactionId {
            eventId = id
        }
        let (content, copyableText) = Self.content(of: msg.kind)
        self.init(
            content: content,
            isOwn: event.isOwn,
            eventId: eventId,
            canBeRepliedTo: event.canBeRepliedTo,
            isPinned: eventId.map(pinnedEventIds.contains) ?? false,
            copyableText: copyableText,
            redactPermission: redactPermission
        )
    }

    private static func content(of kind: MatrixRustSDK.MsgLikeKind) -> (Content, String?) {
        switch kind {
        case let .message(message):
            return content(of: message.msgType)
        case .redacted:
            return (.redacted, nil)
        case .sticker, .poll, .unableToDecrypt, .other, .liveLocation:
            return (.other, nil)
        }
    }

    private static func content(of msgType: MatrixRustSDK.MessageType) -> (Content, String?) {
        switch msgType {
        case let .text(content):
            return (.text, content.body)
        case let .notice(content):
            return (.text, content.body)
        case let .emote(content):
            return (.text, content.body)
        case let .location(content):
            return (.text, content.body)
        case let .image(content):
            return (.image, content.caption)
        case let .video(content):
            return (.video(isPlayingInline: false), content.caption)
        case let .audio(content):
            return (.audio, content.caption)
        case let .file(content):
            return (.file, content.caption)
        case let .gallery(content):
            return (.other, content.body)
        case let .other(_, body):
            return (.other, body)
        }
    }
}

// MARK: - Redact permission (MATRIX-110)

public extension Models.MessageRedactPermission {
    /// Reads what the signed-in account may redact from the room's power
    /// levels. The SDK owns the power-level rules; this only copies its two
    /// answers.
    init(powerLevels: MatrixRustSDK.RoomPowerLevels) {
        self.init(
            canRedactOwn: powerLevels.canOwnUserRedactOwn(),
            canRedactOther: powerLevels.canOwnUserRedactOther()
        )
    }
}
