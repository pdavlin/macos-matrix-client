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
                hasReactions: !content.reactions.isEmpty
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
}
