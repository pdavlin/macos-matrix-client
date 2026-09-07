import Foundation
import MatrixRustSDK
import Models
import Observation
import OSLog
import TimelineSpikeCore

/// One display-ordered change plus its payload.
///
/// Declared here because the production container drains a batch of these and
/// the type lives beside `LiveTimeline` in the app. Field-for-field the same
/// shape: the container reads `change` and `items` and nothing else.
struct TimelineDisplayUpdate {
    let change: TimelineDisplayChange
    let items: [MatrixRustSDK.TimelineItem]
}

/// Stand-in for the room object the container asks about typing and directness.
@MainActor
@Observable
final class HarnessRoom {
    /// No synthetic sender ever types, so the newest-end decoration row never
    /// appears and item index equals table index. The AppKit candidate has no
    /// decoration rows either, which is what keeps the two comparable.
    var typingUserIds: [String] = []
    var members: [MockRoomMember] = []
    /// Direct rooms show read receipts (D-3). Synthetic events carry none, so
    /// the harness runs the group-room branch, matching the candidate's rows.
    let roomInfo: HarnessRoomInfo? = HarnessRoomInfo()
}

struct HarnessRoomInfo {
    let isDirect = false
}

/// Stand-in for `LiveTimeline`: the object the production container reads its
/// display order and its change queue from.
///
/// It is the only bridge between the synthetic world and the production
/// container. Everything below this line is the real thing.
@MainActor
@Observable
final class LiveTimeline {
    private(set) var displayItems: [MatrixRustSDK.TimelineItem] = []
    private(set) var focusedTimelineEventId: MatrixRustSDK.EventOrTransactionId?
    private(set) var scrollToBottomRequests: Int = 0
    /// Held at idle so the oldest-end decoration row never appears; see
    /// `HarnessRoom.typingUserIds` for why decoration rows stay out.
    private(set) var paginating: PaginationStatus = .idle(hitTimelineStart: false)
    /// Held at nil for the same reason: the synthetic store cannot fail a
    /// fetch, so the S-35 failure row never appears in a measured run.
    private(set) var paginationFailure: String?
    let room = HarnessRoom()

    @ObservationIgnored private var pendingDisplayChanges: [TimelineDisplayUpdate] = []
    @ObservationIgnored private let harness: SpikeHarness
    /// Store state the display order was last brought level with.
    @ObservationIgnored private var syncedOldestIndex: Int
    @ObservationIgnored private var syncedItemCount: Int
    @ObservationIgnored private var syncedMutationCount: Int
    /// Set when a batch could not be expressed as a diff and the container was
    /// told to rebuild. Counted so a run that resets can be spotted in the report.
    private(set) var resyncCount = 0

    init(harness: SpikeHarness) {
        self.harness = harness
        let store = harness.store
        self.syncedOldestIndex = store.oldestIndex
        self.syncedItemCount = store.items.count
        self.syncedMutationCount = store.appliedMutationCount
        self.displayItems = Self.displayOrdered(store.items)
    }

    /// The container drains the queue; the harness never calls this.
    func drainDisplayChanges() -> [TimelineDisplayUpdate] {
        defer { pendingDisplayChanges.removeAll(keepingCapacity: true) }
        return pendingDisplayChanges
    }

    func setAtBottom(_: Bool) {}

    /// The container's own 200pt trigger fired. Routing it back through the
    /// harness keeps the pagination pacing — batch size, minimum interval, the
    /// automatic/manual split — identical to the one the candidates ran under,
    /// while the decision of *when* to ask stays the production geometry's.
    func fetchOlderMessages() async {
        harness.viewportDidScroll(distanceFromTop: 0)
    }

    /// Unreachable in a measured run — `paginationFailure` never latches here.
    func retryPagination() {}

    // MARK: - Synthetic → display order

    /// Brings the display order level with the store and queues the changes
    /// that describe the move.
    ///
    /// Called once per SwiftUI update, before the container drains. Cost is
    /// proportional to the change, not to the timeline — a full rescan here
    /// would hide exactly the property S-34 landed.
    func syncFromStore() {
        let store = harness.store
        applyPrepends(store: store)
        applyMutations(store: store)
    }

    private func applyPrepends(store: TimelineStore) {
        let prependedCount = syncedOldestIndex - store.oldestIndex
        guard prependedCount > 0 else { return }
        guard store.items.count == syncedItemCount + prependedCount else {
            resync(store: store)
            return
        }

        // The batch is the oldest `prependedCount` items of the store, and the
        // oldest end of the store is the *end* of the display order.
        let batch = Self.displayOrdered(Array(store.items.prefix(prependedCount)))
        let insertIndex = displayItems.count
        displayItems.append(contentsOf: batch)
        syncedOldestIndex = store.oldestIndex
        syncedItemCount = store.items.count
        pendingDisplayChanges.append(
            TimelineDisplayUpdate(
                change: .insert(index: insertIndex, count: batch.count),
                items: batch
            )
        )
    }

    private func applyMutations(store: TimelineStore) {
        let advanced = store.appliedMutationCount - syncedMutationCount
        guard advanced > 0 else { return }

        // `lastBatch` holds one tick. If more ticks landed than it can name,
        // the queue cannot describe the move and the container rebuilds. That
        // is rare by construction — the storm ticks well below the display
        // rate — and it is recorded rather than papered over.
        let batch = harness.mutationDriver.lastBatch
        guard advanced <= batch.count else {
            resync(store: store)
            return
        }

        syncedMutationCount = store.appliedMutationCount
        let count = displayItems.count
        for mutation in batch.suffix(advanced) {
            guard let storeIndex = store.itemIndex(for: mutation.target) else { continue }
            let displayIndex = TimelineDisplayOrder.displayIndex(ofSdkIndex: storeIndex, count: count)
            guard TimelineDisplayOrder.isValidIndex(displayIndex, count: count) else {
                resync(store: store)
                return
            }
            let item = Self.sdkItem(for: store.items[storeIndex])
            displayItems[displayIndex] = item
            pendingDisplayChanges.append(
                TimelineDisplayUpdate(change: .update(index: displayIndex), items: [item])
            )
        }
    }

    private func resync(store: TimelineStore) {
        resyncCount += 1
        Logger.timelineTableView.info("harness bridge: display order resynchronised from the store")
        displayItems = Self.displayOrdered(store.items)
        syncedOldestIndex = store.oldestIndex
        syncedItemCount = store.items.count
        syncedMutationCount = store.appliedMutationCount
        pendingDisplayChanges.append(TimelineDisplayUpdate(change: .reset, items: []))
    }

    /// Newest first, the order the unflipped table renders bottom-up.
    private static func displayOrdered(_ items: [TimelineSpikeCore.TimelineItem]) -> [MatrixRustSDK.TimelineItem] {
        items.reversed().map(sdkItem(for:))
    }

    static func sdkItem(for item: TimelineSpikeCore.TimelineItem) -> MatrixRustSDK.TimelineItem {
        MatrixRustSDK.TimelineItem(
            event: SyntheticEventAdapter.event(for: item),
            uniqueId: TimelineUniqueId(id: String(item.id.rawValue))
        )
    }
}
