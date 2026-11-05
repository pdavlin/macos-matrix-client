import Foundation

/// What an edit replaces in a message (MATRIX-109, M2-B2).
public enum ComposerEditKind: Equatable, Sendable {
    /// A text message: the edit replaces the body.
    case message
    /// A media message: the edit replaces the caption.
    case caption
}

/// The new content of an edit, with no SDK types. `Core` turns it into the
/// SDK's `EditedContent`.
public enum ComposerEditContent: Equatable, Sendable {
    /// A text message: the same markdown and mentions as a normal send.
    case message(ComposerOutgoingMessage)
    /// A media caption: plain text, with each chip as "@name", and the
    /// mentioned users. A nil text removes the caption.
    ///
    /// The caption goes as plain text because the verified edit call takes
    /// the formatted caption as HTML, and the composer has no SDK call that
    /// makes HTML from markdown. Plain text keeps a chip readable.
    case caption(text: String?, mentionedUserIds: [String])
}

/// What Return does in edit mode.
public enum ComposerEditSaveDecision: Equatable, Sendable {
    /// Send the edit, then leave edit mode.
    case send(ComposerEditContent)
    /// The text did not change: leave edit mode and send nothing.
    case finishWithoutSending
    /// The text cannot be sent (an empty text message): stay in edit mode.
    case keepEditing
}

/// The composer's edit-mode rules (MATRIX-109, M2-B2).
///
/// Pure logic with no SDK or UI types, so it is unit-tested in `ModelsTests`.
/// The composer text is draft text (`MentionMarkdown`): typed text, and each
/// mention chip as a `matrix.to` pill link.
///
/// Usage:
/// ```swift
/// switch ComposerEdit.saveDecision(kind: .message, originalDraftText: old, draftText: new) {
/// case let .send(content): // call the SDK
/// case .finishWithoutSending: // leave edit mode
/// case .keepEditing: break
/// }
/// ```
public enum ComposerEdit {
    /// Whether the Up arrow starts an edit of the last own message: only in
    /// an empty composer with no attachment, and not in edit mode.
    ///
    /// - Parameters:
    ///   - draftText: The composer text.
    ///   - attachmentCount: The number of pending attachments.
    ///   - isEditing: Whether the composer is in edit mode.
    public static func startsEditOnUpArrow(draftText: String, attachmentCount: Int, isEditing: Bool) -> Bool {
        draftText.isEmpty && attachmentCount == 0 && !isEditing
    }

    /// The one-line preview of the original text that the edit bar shows:
    /// each chip as "@name", and line breaks as spaces.
    ///
    /// - Parameter draftText: The original text as draft text.
    public static func previewText(fromDraftText draftText: String) -> String {
        MentionMarkdown.plainText(for: MentionMarkdown.segments(fromDraftText: draftText))
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// What Return does in edit mode.
    ///
    /// - Parameters:
    ///   - kind: Whether the edit replaces a message body or a caption.
    ///   - originalDraftText: The text the edit started with.
    ///   - draftText: The composer text now.
    /// - Returns: The content to send, or what to do instead.
    public static func saveDecision(
        kind: ComposerEditKind,
        originalDraftText: String,
        draftText: String
    ) -> ComposerEditSaveDecision {
        if draftText == originalDraftText {
            return .finishWithoutSending
        }
        let isBlank = draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch kind {
        case .message:
            // An edit cannot empty a message; Delete does that.
            if isBlank { return .keepEditing }
            return .send(.message(MentionMarkdown.outgoingMessage(fromDraftText: draftText)))
        case .caption:
            let segments = MentionMarkdown.segments(fromDraftText: draftText)
            let text = MentionMarkdown.plainText(for: segments).trimmingCharacters(in: .whitespacesAndNewlines)
            return .send(.caption(
                text: isBlank ? nil : text,
                mentionedUserIds: MentionMarkdown.mentionedUserIds(in: segments)
            ))
        }
    }
}
