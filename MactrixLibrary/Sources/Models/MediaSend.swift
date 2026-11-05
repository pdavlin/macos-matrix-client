import Foundation

/// How the composer sends its pending attachments (MATRIX-106).
public enum MediaSendPlan: Equatable, Sendable {
    /// One attachment: `sendImage`, `sendVideo`, `sendAudio`, or `sendFile`
    /// by its kind.
    case single(ComposerAttachment)
    /// Two or more attachments: one `sendGallery` call, in composer order.
    case gallery([ComposerAttachment])

    /// - Parameter attachments: the pending attachments, in composer order.
    /// - Returns: nil for no attachment.
    public init?(attachments: [ComposerAttachment]) {
        switch attachments.count {
        case 0:
            return nil
        case 1:
            self = .single(attachments[0])
        default:
            self = .gallery(attachments)
        }
    }

    /// The attachments, in composer order.
    public var attachments: [ComposerAttachment] {
        switch self {
        case let .single(attachment):
            [attachment]
        case let .gallery(attachments):
            attachments
        }
    }
}

/// The caption of a media send: the composer text with the same markdown,
/// pill, and mention handling as a text message (MATRIX-105).
public struct MediaCaption: Equatable, Sendable {
    /// The caption markdown, with each chip as a `matrix.to` pill link.
    public let markdown: String
    /// The users for `Mentions.userIds`. Empty when the caption has no chip.
    public let mentionedUserIds: [String]

    public init(markdown: String, mentionedUserIds: [String]) {
        self.markdown = markdown
        self.mentionedUserIds = mentionedUserIds
    }

    /// The caption for the composer draft text.
    ///
    /// - Parameter draftText: the composer binding value (`MentionMarkdown`
    ///   draft text).
    /// - Returns: nil when the text is empty or only whitespace, so the media
    ///   goes with no caption.
    public static func make(fromDraftText draftText: String) -> MediaCaption? {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let outgoing = MentionMarkdown.outgoingMessage(fromDraftText: trimmed)
        return MediaCaption(markdown: outgoing.markdown, mentionedUserIds: outgoing.mentionedUserIds)
    }
}

/// The thumbnail fields of an SDK info struct (`ThumbnailInfo`), and the
/// bytes to upload as the thumbnail.
public struct MediaThumbnailSendInfo: Equatable, Sendable {
    public let data: Data
    public let filename: String
    public let width: UInt64
    public let height: UInt64
    public let mimeType: String
    public let size: UInt64
}

/// The info fields for one attachment, in the shape of the SDK info structs
/// (`ImageInfo`, `VideoInfo`, `AudioInfo`, `FileInfo`).
///
/// Each field is nil if it is unknown or if the kind does not use it. The
/// Core mapping copies the fields into the SDK struct for `kind` and adds
/// nothing, so this type holds all of the rules.
public struct MediaSendInfo: Equatable, Sendable {
    public let kind: MediaSendKind
    public let mimeType: String?
    public let size: UInt64?
    /// Images and videos only.
    public let width: UInt64?
    /// Images and videos only.
    public let height: UInt64?
    /// Videos and audio only.
    public let duration: TimeInterval?
    /// Images only.
    public let isAnimated: Bool?
    /// Images and videos only.
    public let thumbnail: MediaThumbnailSendInfo?

    /// Builds the info for an attachment from its measured values.
    ///
    /// - Parameter attachment: a pending attachment. An attachment with no
    ///   measurement yet gets the type and size only.
    public init(attachment: ComposerAttachment) {
        let measurement = attachment.measurement ?? .empty
        let isVisual = attachment.kind == .image || attachment.kind == .video
        let isTimed = attachment.kind == .video || attachment.kind == .audio

        kind = attachment.kind
        mimeType = attachment.mimeType
        size = attachment.byteCount
        width = isVisual ? measurement.width : nil
        height = isVisual ? measurement.height : nil
        duration = isTimed ? measurement.duration : nil
        isAnimated = attachment.kind == .image ? measurement.isAnimated : nil
        thumbnail = isVisual ? measurement.thumbnail.map {
            MediaThumbnailSendInfo(
                data: $0.data,
                filename: MediaThumbnailPolicy.filename(forMimeType: $0.mimeType),
                width: $0.width,
                height: $0.height,
                mimeType: $0.mimeType,
                size: $0.size
            )
        } : nil
    }
}

/// Everything one media send needs, with no SDK type: the plan, the caption,
/// and the reply target.
public struct MediaSendRequest: Equatable, Sendable {
    public let plan: MediaSendPlan
    public let caption: MediaCaption?
    /// The event id of the reply target, for `inReplyTo`.
    public let inReplyTo: String?

    public init(plan: MediaSendPlan, caption: MediaCaption?, inReplyTo: String?) {
        self.plan = plan
        self.caption = caption
        self.inReplyTo = inReplyTo
    }

    /// The request for the composer state.
    ///
    /// - Parameters:
    ///   - attachments: the pending attachments, in composer order.
    ///   - draftText: the composer text, which becomes the caption.
    ///   - inReplyTo: the reply target event id, or nil.
    /// - Returns: nil when there is no attachment, so the composer sends text.
    public static func make(
        attachments: [ComposerAttachment],
        draftText: String,
        inReplyTo: String?
    ) -> MediaSendRequest? {
        guard let plan = MediaSendPlan(attachments: attachments) else { return nil }
        return MediaSendRequest(plan: plan, caption: MediaCaption.make(fromDraftText: draftText), inReplyTo: inReplyTo)
    }
}

/// One media send that runs in the SDK: the cancel hook for MATRIX-107.
///
/// Core makes a ticket for each `sendImage`/`sendVideo`/`sendAudio`/
/// `sendFile`/`sendGallery` call and keeps the join handle with it. The
/// ticket ends when `join()` returns.
public struct MediaSendTicket: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The filenames, in composer order. The SDK puts the same name in the
    /// local echo content.
    public let filenames: [String]
    public let isGallery: Bool
    /// The transaction id of the local echo, after a cancel by local echo
    /// matched this ticket. Nil before that.
    public var localEchoTransactionId: String?

    public init(id: UUID = UUID(), filenames: [String], isGallery: Bool, localEchoTransactionId: String? = nil) {
        self.id = id
        self.filenames = filenames
        self.isGallery = isGallery
        self.localEchoTransactionId = localEchoTransactionId
    }
}

/// Finds the media send ticket for a local echo (MATRIX-106, for the
/// MATRIX-107 cancel button).
///
/// The join handle carries no transaction id, so the match uses what the
/// local echo shows: its filename. Sends from one composer go in order, so
/// the oldest open ticket with that filename is the match.
public enum MediaSendCorrelation {
    /// - Parameters:
    ///   - transactionId: the local echo transaction id.
    ///   - filename: the filename in the local echo content. Nil for a
    ///     gallery.
    ///   - tickets: the open tickets, oldest first.
    /// - Returns: the index of the ticket already bound to `transactionId`.
    ///   If there is none: for a filename, the oldest unbound single ticket
    ///   with that filename; for a gallery, the oldest unbound gallery
    ///   ticket. Nil when nothing matches.
    public static func ticketIndex(
        forTransactionId transactionId: String,
        filename: String?,
        in tickets: [MediaSendTicket]
    ) -> Int? {
        if let bound = tickets.firstIndex(where: { $0.localEchoTransactionId == transactionId }) {
            return bound
        }
        return tickets.firstIndex { ticket in
            guard ticket.localEchoTransactionId == nil else { return false }
            if let filename {
                let name = (filename as NSString).lastPathComponent
                return !ticket.isGallery && ticket.filenames == [name]
            }
            return ticket.isGallery
        }
    }
}
