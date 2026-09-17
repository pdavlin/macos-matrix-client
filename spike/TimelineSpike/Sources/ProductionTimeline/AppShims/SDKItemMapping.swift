import MatrixRustSDK
import Models
import OSLog

/// The SDK-item-to-row mapping, mirroring `MatrixRustSDK+Extensions.swift` in
/// the app target.
///
/// It lives in the harness rather than behind a symlink because the app's copy
/// is one member of a file full of SDK conformances the spike has no shim for.
/// The logic is the mapping the container relies on: total, one row per item,
/// `.unsupported` rather than a drop.
extension MatrixRustSDK.TimelineItem {
    var row: Models.TimelineRow {
        if let virtual = asVirtual() {
            return .virtual(uniqueId: uniqueId().id, item: virtual.asModel)
        }

        guard let event = asEvent() else {
            Logger.timelineRowMapping.warning(
                "Timeline item has neither event nor virtual content (uniqueId: \(self.uniqueId().id))"
            )
            return .unsupported(uniqueId: uniqueId().id)
        }

        switch event.content {
        case let .msgLike(content: content):
            return .message(
                uniqueId: uniqueId().id,
                event: event,
                kind: content.rowKind,
                heightFingerprint: content.heightFingerprint(event: event)
            )
        case .state:
            return .state(uniqueId: uniqueId().id, event: event, name: event.content.description)
        }
    }
}

extension MatrixRustSDK.MsgLikeContent {
    /// Coarse render shape, used for view recycling (S-34). Same table as the
    /// app's.
    var rowKind: Models.MessageRowKind {
        switch kind {
        case let .message(content: content):
            switch content.msgType {
            case .text, .notice, .emote:
                return .text
            case .image, .video, .gallery:
                return .media
            case .audio, .file:
                return .attachment
            case .location, .other:
                return .other
            }
        case .sticker:
            return .media
        case .poll, .redacted, .unableToDecrypt, .other, .liveLocation:
            return .other
        }
    }

    /// Height-relevant content fingerprint (MATRIX-63). Same table as the app's,
    /// over the fields the shim's content carries.
    ///
    /// The shim has no edit flag, reply, thread summary or send state, so those
    /// stay at their neutral values. What the storm actually mutates — the body
    /// text and the reaction tallies — is exactly what the harness has to
    /// fingerprint for the measurement to mean anything.
    func heightFingerprint(event: MatrixRustSDK.EventTimelineItem) -> Models.TimelineRowHeightFingerprint {
        Models.TimelineRowHeightFingerprint(
            body: bodyGeometry,
            senderName: event.senderDisplayName ?? event.sender,
            reactions: Models.ReactionStripGeometry(
                reactions: reactions.lazy.map { (key: $0.key, senderCount: $0.senders.count) },
                hasReadReceipts: !event.userReadReceipts.isEmpty
            )
        )
    }

    private var bodyGeometry: Models.MessageBodyGeometry {
        switch kind {
        case let .message(content: content):
            // The harness encodes image geometry into the body string, so the
            // body text carries the media dimensions here rather than the
            // dedicated fields.
            return .init(variant: content.msgType.rawValue, text: content.body)
        case .sticker:
            return .init(variant: "sticker", text: "")
        case .poll:
            return .init(variant: "poll", text: "")
        case .redacted:
            return .init(variant: "redacted", text: "")
        case .unableToDecrypt:
            return .init(variant: "utd", text: "")
        case .other:
            return .init(variant: "other-event", text: "")
        case .liveLocation:
            return .init(variant: "live-location", text: "")
        }
    }
}
