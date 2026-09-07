import Foundation
import MatrixRustSDK
import Models
import TimelineSpikeCore

/// Turns a synthetic event into the event shape the production row layer
/// consumes.
///
/// This is the seam the story names: the container takes `TimelineRow` values
/// carrying `Models.EventTimelineItem`s, and neither the row model nor that
/// protocol knows anything about the SDK. The adapter is the only place the
/// two vocabularies meet.
enum SyntheticEventAdapter {
    static func event(for item: TimelineSpikeCore.TimelineItem) -> MatrixRustSDK.EventTimelineItem {
        let spikeEvent = item.event
        return MatrixRustSDK.EventTimelineItem(
            eventOrTransactionId: EventOrTransactionId(id: String(spikeEvent.id.rawValue)),
            sender: spikeEvent.sender.id,
            senderDisplayName: spikeEvent.sender.displayName,
            date: spikeEvent.timestamp,
            content: .msgLike(content: content(for: spikeEvent))
        )
    }

    private static func content(for event: SpikeEvent) -> MatrixRustSDK.MsgLikeContent {
        MatrixRustSDK.MsgLikeContent(kind: kind(for: event.content), reactions: reactions(for: event))
    }

    private static func kind(for content: EventContent) -> MatrixRustSDK.MsgLikeKind {
        switch content {
        case let .text(body):
            // `.text` maps to the `.text` row kind, so the container recycles
            // text rows against text rows exactly as it does in the app.
            return .message(content: MatrixRustSDK.MessageContent(msgType: .text, body: body.text))
        case let .image(placeholder):
            // Aspect ratio and intrinsic width travel in the body string: the
            // SDK message shapes the harness can build carry no image info, and
            // a media row that does not know its ratio measures a wrong height.
            return .message(
                content: MatrixRustSDK.MessageContent(
                    msgType: .image,
                    body: MediaGeometry.encode(
                        aspectRatio: placeholder.aspectRatio,
                        intrinsicWidth: placeholder.intrinsicWidth,
                        caption: placeholder.caption
                    )
                )
            )
        }
    }

    /// Reaction senders are synthesised from the tally. The row layer counts
    /// senders to draw the strip, so the count has to be the tally rather than
    /// a placeholder, otherwise the reaction row measures the wrong height.
    private static func reactions(for event: SpikeEvent) -> [MatrixRustSDK.Reaction] {
        event.reactions.map { reaction in
            MatrixRustSDK.Reaction(
                key: reaction.key,
                senders: (0 ..< max(0, reaction.count)).map { index in
                    ReactionSender(senderId: "@reactor\(index):spike", date: event.timestamp)
                }
            )
        }
    }

    /// The event identifier behind a row, recovered from the row's unique id.
    ///
    /// Row identity is the synthetic index written as a string, so the reverse
    /// map is a parse rather than a lookup table.
    static func eventID(forRowId rowId: String) -> EventID? {
        Int(rowId).map(EventID.init)
    }
}
