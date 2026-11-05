import Foundation
import MatrixRustSDK
import Models
import OSLog

/// One message the composer edits (MATRIX-109, M2-B2).
///
/// Built only for an own message that the SDK marks editable and whose
/// content the composer can edit: a text message, or the caption of a media
/// message. Notices, emotes, and locations are left out, because the edit
/// sends text content and would change their message type.
public struct MessageEditTarget: Equatable, Identifiable {
    /// The event ID, or the transaction ID of a local echo. The SDK edits
    /// both.
    public let itemId: MatrixRustSDK.EventOrTransactionId
    /// Whether the edit replaces the body or the caption.
    public let kind: ComposerEditKind
    /// The text the composer starts with, as draft text.
    ///
    /// It is the message body (or caption) as sent. For a message this app
    /// sent, the body is the markdown the composer made, so each `matrix.to`
    /// pill link becomes a chip again, as a saved draft does (MATRIX-105).
    public let originalDraftText: String

    public var id: String {
        itemId.id
    }

    /// - Returns: nil when the composer cannot edit the event.
    public init?(event: MatrixRustSDK.EventTimelineItem) {
        guard event.isOwn, event.isEditable,
              case let .msgLike(content: msgLike) = event.content,
              let editable = Self.editableContent(of: msgLike.kind)
        else { return nil }
        self.itemId = event.eventOrTransactionId
        self.kind = editable.kind
        self.originalDraftText = editable.text
    }

    /// The edit kind and the current text of content the composer can edit,
    /// or nil for any other content. Exhaustive with no `default`, so a new
    /// SDK case has to be sorted here.
    static func editableContent(of kind: MatrixRustSDK.MsgLikeKind) -> (kind: ComposerEditKind, text: String)? {
        guard case let .message(message) = kind else { return nil }
        switch message.msgType {
        case let .text(content):
            return (.message, content.body)
        case let .image(content):
            return (.caption, content.caption ?? "")
        case let .video(content):
            return (.caption, content.caption ?? "")
        case let .audio(content):
            return (.caption, content.caption ?? "")
        case let .file(content):
            return (.caption, content.caption ?? "")
        case .notice, .emote, .location, .gallery, .other:
            return nil
        }
    }
}

/// Why an edit did not start.
public enum MessageEditError: Error {
    /// The room timeline has not loaded yet.
    case timelineNotReady
}

// MARK: - Edit (MATRIX-109)

public extension LiveTimeline {
    /// Asks the composer to edit a message. The composer reads
    /// `pendingComposerEdit`, starts edit mode, and sets it back to nil.
    ///
    /// - Parameter event: The message. Nothing happens if the composer
    ///   cannot edit it.
    func requestEdit(of event: MatrixRustSDK.EventTimelineItem) {
        guard let target = MessageEditTarget(event: event) else {
            Logger.liveTimeline.error("edit requested for a message that is not editable: \(event.eventOrTransactionId.id)")
            return
        }
        pendingComposerEdit = target
    }

    /// The newest message in this timeline that the composer can edit, for
    /// the Up arrow in an empty composer.
    func lastEditTarget() -> MessageEditTarget? {
        for item in displayItems {
            if let event = item.asEvent(), let target = MessageEditTarget(event: event) {
                return target
            }
        }
        return nil
    }

    /// Sends an edit through the SDK.
    ///
    /// The content is built the same way as a normal send: a message from
    /// `messageEventContentFromMarkdown`, with `withMentions` when the text
    /// has chips; a caption with its mentions.
    ///
    /// - Parameters:
    ///   - target: The message to edit.
    ///   - content: The new content, from `ComposerEdit.saveDecision`.
    /// - Throws: `MessageEditError.timelineNotReady`, or the SDK error.
    func edit(_ target: MessageEditTarget, with content: ComposerEditContent) async throws {
        guard let timeline else { throw MessageEditError.timelineNotReady }
        let newContent: MatrixRustSDK.EditedContent
        switch content {
        case let .message(outgoing):
            let markdownContent = messageEventContentFromMarkdown(md: outgoing.markdown)
            let message: RoomMessageEventContentWithoutRelation = outgoing.mentionedUserIds.isEmpty
                ? markdownContent
                : markdownContent.withMentions(mentions: MatrixRustSDK.Mentions(userIds: outgoing.mentionedUserIds, room: false))
            newContent = .roomMessage(content: message)
        case let .caption(text, mentionedUserIds):
            let mentions: MatrixRustSDK.Mentions? = mentionedUserIds.isEmpty
                ? nil
                : MatrixRustSDK.Mentions(userIds: mentionedUserIds, room: false)
            newContent = .mediaCaption(caption: text, formattedCaption: nil, mentions: mentions)
        }
        try await timeline.edit(eventOrTransactionId: target.itemId, newContent: newContent)
        Logger.liveTimeline.info("edited \(target.id)")
    }
}
