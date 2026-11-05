import Foundation
import MatrixRustSDK
import Models

// MARK: - Transcript line (MATRIX-113)

public extension Models.MessageTranscriptLine {
    /// Builds a transcript line from an SDK timeline message.
    ///
    /// Every switch is exhaustive with no `default`, so a new SDK case has to
    /// be given a transcript body here.
    ///
    /// - Parameters:
    ///   - event: The timeline event.
    ///   - msg: The event's message-like content.
    ///   - displayIndex: The row's index in the display order (0 is newest).
    init(event: MatrixRustSDK.EventTimelineItem, msg: MatrixRustSDK.MsgLikeContent, displayIndex: Int) {
        self.init(
            displayIndex: displayIndex,
            sender: Self.senderName(userId: event.sender, profile: event.senderProfileDetails),
            date: event.date,
            body: Self.body(of: msg.kind)
        )
    }

    private static func body(of kind: MatrixRustSDK.MsgLikeKind) -> Body {
        switch kind {
        case let .message(message):
            return body(of: message.msgType)
        case let .sticker(body: body, info: _, source: _):
            return .sticker(body)
        case let .poll(question: question, kind: _, maxSelections: _, answers: _, votes: _, endTime: _, hasBeenEdited: _):
            return .poll(question: question)
        case .redacted:
            return .redacted
        case .unableToDecrypt:
            return .unableToDecrypt
        case .other, .liveLocation:
            return .unsupported
        }
    }

    private static func body(of msgType: MatrixRustSDK.MessageType) -> Body {
        switch msgType {
        case let .text(content):
            return .text(content.body)
        case let .notice(content):
            return .text(content.body)
        case let .emote(content):
            return .text(content.body)
        case let .location(content):
            return .text(content.body)
        case let .image(content):
            return .media(.image, filename: content.filename, caption: content.caption)
        case let .video(content):
            return .media(.video, filename: content.filename, caption: content.caption)
        case let .audio(content):
            return .media(.audio, filename: content.filename, caption: content.caption)
        case let .file(content):
            return .media(.file, filename: content.filename, caption: content.caption)
        case let .gallery(content):
            return .gallery(content.body)
        case let .other(_, body):
            return .text(body)
        }
    }
}
