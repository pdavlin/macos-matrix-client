import Foundation
import MatrixRustSDK
import Models
import OSLog

/// One item of a member room's timeline, read once from the SDK and stored
/// for the merged timeline (MATRIX-142 Phase B).
///
/// The merge engine and the row builder read these values on every
/// recompute. They are stored, so a recompute makes no FFI call: the SDK
/// item is read once, when the merged timeline first sees it.
struct MergedLiveItem: MergedTimelineRowItem {
    /// The SDK's unique identifier of the item in its room's timeline.
    let mergedItemId: String
    let mergedItemKind: MergedTimelineItemKind
    /// The item's row, with the merged identifier, before grouping.
    let mergedRow: Models.TimelineRow
    let mergedContentRevision: Int
    let mergedReceiptEventId: String?
    /// The event's identifier, for focus lookups. Nil for a virtual item.
    let eventOrTransactionId: MatrixRustSDK.EventOrTransactionId?
    /// The message's send-target activity, or nil when the item is not a
    /// message.
    let messageActivity: MergedMessageActivity?
    /// The SDK item. Held so that its object identity stays valid as the
    /// cache key (`MergedLiveTimeline.Member.updateItems`).
    let item: MatrixRustSDK.TimelineItem

    /// Reads `item` once.
    ///
    /// - Parameters:
    ///   - item: the SDK item, from the member's `LiveTimeline.timelineItems`.
    ///   - roomId: the member room, for the merged row identifier.
    ///   - revision: a value no earlier item of this merged timeline used.
    init(item: MatrixRustSDK.TimelineItem, roomId: String, revision: Int) {
        let uniqueId = item.uniqueId().id
        let rowId = MergedTimelineEntryID.item(roomId: roomId, itemId: uniqueId)
        self.item = item
        mergedItemId = uniqueId
        mergedContentRevision = revision

        if let virtual = item.asVirtual() {
            mergedItemKind = switch virtual {
            case .dateDivider: .dateDivider
            case .readMarker: .readMarker
            case .timelineStart: .otherVirtual
            }
            // The merge drops the SDK's virtual items and makes its own, so
            // this row is never shown.
            mergedRow = .virtual(uniqueId: rowId, item: virtual.asModel)
            mergedReceiptEventId = nil
            eventOrTransactionId = nil
            messageActivity = nil
            return
        }

        guard let event = item.asEvent() else {
            Logger.timelineRowMapping.warning("merged timeline: item \(uniqueId) has neither event nor virtual content")
            mergedItemKind = .otherVirtual
            mergedRow = .unsupported(uniqueId: rowId)
            mergedReceiptEventId = nil
            eventOrTransactionId = nil
            messageActivity = nil
            return
        }

        // A local echo is not on the server yet, even after the send queue
        // reports it sent: the merge orders it after every server event.
        if event.isRemote {
            mergedItemKind = .event(serverTimestamp: event.timestamp.date)
        } else {
            mergedItemKind = .localEcho(createdAt: (event.localCreatedAt ?? event.timestamp).date)
        }
        mergedRow = MatrixRustSDK.TimelineItem.row(for: event, uniqueId: rowId)
        eventOrTransactionId = event.eventOrTransactionId
        if event.isRemote, case let .eventId(eventId) = event.eventOrTransactionId {
            mergedReceiptEventId = eventId
        } else {
            mergedReceiptEventId = nil
        }
        if case .msgLike = event.content {
            messageActivity = MergedMessageActivity(isOwn: event.isOwn, date: event.timestamp.date)
        } else {
            messageActivity = nil
        }
    }
}

extension LiveTimeline {
    /// Sends a public read receipt for one event of this room (MATRIX-142).
    ///
    /// The merged timeline sends each member room a receipt for its own
    /// newest visible event, through this room's timeline:
    /// `Timeline.sendReadReceipt(receiptType:eventId:)`.
    ///
    /// - Parameter eventId: the event the receipt names.
    /// - Returns: false when the timeline has not loaded or the call failed.
    @discardableResult
    func sendReadReceipt(eventId: String) async -> Bool {
        guard let timeline else {
            Logger.liveTimeline.error("read receipt: the timeline of \(self.room.id) has not loaded")
            return false
        }
        do {
            try await timeline.sendReadReceipt(receiptType: .read, eventId: eventId)
            return true
        } catch {
            Logger.liveTimeline.error("failed to send read receipt in \(self.room.id): \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
