import Foundation
import MatrixRustSDK
import Models

// MARK: - Height-relevant content fingerprint (MATRIX-63)

/// Builds a row's height fingerprint from SDK content.
///
/// It sits beside the row mapping rather than inside it: the mapping file is
/// already at the file-length limit, and this is one self-contained concern —
/// the translation from SDK content into the height inputs the row view lays
/// out.
extension MatrixRustSDK.MsgLikeContent {
    /// Height-relevant content fingerprint for this message (MATRIX-63).
    ///
    /// Built from the same content `ChatMessageView` lays out, branch for
    /// branch, so the fingerprint and the view can only disagree if this
    /// mapping is wrong. Every switch is exhaustive with no `default`: a new SDK
    /// case has to be given a variant here rather than silently inheriting one.
    ///
    /// Cheap on purpose — it runs for every mapped item, including a 10k-row
    /// reset. Everything it reads is a stored property or a short SDK accessor;
    /// the one allocation is the pill array. A reply row pays one FFI call,
    /// for its quote; `LiveTimeline` already reads the same details of every
    /// reply on each diff batch.
    public func heightFingerprint(event: MatrixRustSDK.EventTimelineItem) -> Models.TimelineRowHeightFingerprint {
        Models.TimelineRowHeightFingerprint(
            body: bodyGeometry,
            // The quote, not only its presence (MATRIX-230): the SDK replaces
            // an unavailable quote with the loaded one through a row update,
            // and the two differ by lines. Not the target's id: a reply
            // relation does not move under an edit.
            replyQuote: inReplyTo?.event().replyQuote,
            // Presence only: the summary draws a fixed one-line label, so a new
            // reply changes its text and not its height. A summary with no
            // reply draws no chip (MATRIX-216).
            hasThreadSummary: ThreadRootRule.isThreadRoot(replyCount: threadSummary?.numReplies()),
            sendFailureMessage: event.sendFailureMessage,
            senderName: event.fingerprintSenderName,
            reactions: Models.ReactionStripGeometry(
                reactions: event.reactions.lazy.map { (key: $0.key, senderCount: $0.senders.count) },
                // `readReceipts`, not the mapped `userReadReceipts`: the model
                // property rebuilds the dictionary, and only emptiness is read.
                hasReadReceipts: !event.readReceipts.isEmpty
            )
        )
    }

    /// The body branch and the text it lays out.
    private var bodyGeometry: Models.MessageBodyGeometry {
        switch kind {
        case let .message(content: content):
            return content.bodyGeometry
        case let .sticker(body: body, info: _, source: _):
            return .init(variant: "sticker", text: body)
        case let .poll(
            question: question,
            kind: _,
            maxSelections: _,
            answers: _,
            votes: _,
            endTime: _,
            hasBeenEdited: hasBeenEdited
        ):
            return .init(variant: "poll", text: question, isEdited: hasBeenEdited)
        case .redacted:
            // A constant string, so the variant carries the whole identity.
            return .init(variant: "redacted", text: "")
        case let .unableToDecrypt(msg: encrypted):
            // The cause picks the wording the UTD view draws, so it belongs in
            // the variant rather than in the text.
            return .init(variant: "utd.\(Models.UnableToDecryptCause(encrypted: encrypted))", text: "")
        case let .other(eventType: eventType):
            return .init(variant: "other-event", text: eventType.description)
        case let .liveLocation(content: content):
            return .init(variant: "live-location", text: content.description ?? "")
        }
    }
}

public extension MatrixRustSDK.MessageContent {
    /// The body branch `ChatMessageView.messageBody(_:)` takes, and the text it
    /// lays out (MATRIX-63).
    var bodyGeometry: Models.MessageBodyGeometry {
        switch msgType {
        case let .text(content: content):
            // `FormattedBodyView` renders the HTML body when there is one and
            // the raw body otherwise, so both decide the line count.
            return .init(
                variant: "text",
                text: content.body,
                formattedText: content.formatted?.format == .html ? content.formatted?.body : nil,
                isEdited: isEdited
            )
        case let .notice(content: content):
            return .init(variant: "notice", text: content.body, isEdited: isEdited)
        case let .emote(content: content):
            return .init(variant: "emote", text: content.body, isEdited: isEdited)
        case let .image(content: content):
            return .init(
                variant: "image",
                text: "",
                isEdited: isEdited,
                mediaWidth: content.info?.width,
                mediaHeight: content.info?.height,
                secondaryText: content.caption
            )
        case let .video(content: content):
            return .init(
                variant: "video",
                text: "",
                isEdited: isEdited,
                mediaWidth: content.info?.width,
                mediaHeight: content.info?.height,
                // Without a thumbnail the row falls back to a minimum height.
                hasMediaThumbnail: content.info?.thumbnailSource != nil,
                secondaryText: content.caption
            )
        case let .audio(content: content):
            return .init(variant: "audio", text: content.filename, isEdited: isEdited, secondaryText: content.caption)
        case let .file(content: content):
            return .init(variant: "file", text: content.filename, isEdited: isEdited, secondaryText: content.caption)
        case let .gallery(content: content):
            return .init(variant: "gallery", text: content.body, isEdited: isEdited)
        case let .location(content: content):
            return .init(variant: "location", text: content.body, isEdited: isEdited, secondaryText: content.geoUri)
        case let .other(msgtype: msgtype, body: body):
            return .init(variant: "other-msgtype.\(msgtype)", text: body, isEdited: isEdited)
        }
    }
}

public extension MatrixRustSDK.EmbeddedEventDetails {
    /// The quote a reply draws for these details (MATRIX-230). The row's height
    /// fingerprint and `UI.ReplyQuoteView` both read it.
    var replyQuote: Models.ReplyQuoteGeometry {
        switch self {
        case .unavailable, .pending:
            return .placeholder
        case let .ready(content: content, sender: sender, senderProfile: senderProfile, timestamp: _, eventOrTransactionId: _):
            guard case let .ready(displayName: displayName, displayNameAmbiguous: _, avatarUrl: _, status: _, call: _) = senderProfile,
                  let displayName
            else {
                return .quote(sender: sender, text: content.description)
            }
            return .quote(sender: displayName, text: content.description)
        case let .error(message: message):
            return .failed(message: message)
        }
    }
}

public extension Models.TimelineRow {
    /// The event a reply row quotes, or nil for a row that quotes nothing
    /// (MATRIX-230). One FFI call for a reply row, none for any other row.
    var quotedEventId: String? {
        guard heightFingerprint?.replyQuote != nil,
              case let .message(_, event, _, _) = self,
              let event = event as? MatrixRustSDK.EventTimelineItem,
              case let .msgLike(content: content) = event.content
        else {
            return nil
        }
        return content.inReplyTo?.eventId()
    }
}

public extension MatrixRustSDK.EventTimelineItem {
    /// The failure banner's message, or nil when the send did not fail.
    ///
    /// Reads `localSendState` rather than the mapped `sendState` so the mapping
    /// pays no enum round-trip per row.
    var sendFailureMessage: String? {
        guard case let .sendingFailed(error: error, isRecoverable: _) = localSendState else { return nil }
        return error.userMessage
    }

    /// The name the profile header draws, resolved exactly as the header
    /// resolves it.
    var fingerprintSenderName: String {
        guard case let .ready(displayName: displayName, displayNameAmbiguous: _, avatarUrl: _) = senderProfileDetails,
              let displayName
        else {
            return sender
        }
        return displayName
    }
}
