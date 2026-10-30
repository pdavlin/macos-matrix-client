#if DEBUG
    import Foundation
    import Models
    import Observation
    import TimelineSpikeCore

    /// A spike event as the iOS row layer sees it (MATRIX-87).
    ///
    /// The iOS twin of the Mac gate's `SyntheticEventAdapter`. Message rows
    /// that are not SDK events render through `TimelineRowContent`'s fallback:
    /// the real sender header and body chrome around a plain `Text` body.
    /// Image placeholders draw as the one-line label iOS media rows show until
    /// MATRIX-86.
    struct TimelineGateEvent: TimelineTextEvent {
        let event: SpikeEvent

        var body: String {
            switch event.content {
            case let .text(text):
                text.text
            case let .image(placeholder):
                "Image: \(placeholder.caption ?? "untitled")"
            }
        }

        /// Senders are synthesized from the tally: the strip counts senders,
        /// so the count must be the tally for the row to measure right.
        var reactionPills: [TimelineReactionPill] {
            event.reactions.map { reaction in
                TimelineReactionPill(
                    key: reaction.key,
                    senders: (0 ..< max(0, reaction.count)).map {
                        TimelineReactionPill.Sender(senderId: "@reactor\($0):spike", date: event.timestamp)
                    }
                )
            }
        }

        var sender: String { event.sender.id }
        var date: Date { event.timestamp }
        var isRemote: Bool { true }
        var senderProfileDetails: ProfileDetails {
            .ready(displayName: event.sender.displayName, displayNameAmbiguous: false, avatarUrl: nil)
        }

        var isOwn: Bool { false }
        var isEditable: Bool { false }
        var sendState: LocalSendState? { nil }
        var localCreatedAt: UInt64? { nil }
        var userReadReceipts: [String: Receipt] { [:] }
        var canBeRepliedTo: Bool { false }
        var userId: String { event.sender.id }
        var displayName: String? { event.sender.displayName }
        var avatarUrl: String? { nil }

        /// The row for one store item. Row identity is the synthetic index as
        /// a string, as on the Mac gate, so a row maps back to its event with
        /// a parse.
        static func row(for item: TimelineSpikeCore.TimelineItem) -> TimelineRow {
            let event = TimelineGateEvent(event: item.event)
            return .message(
                uniqueId: String(item.id.rawValue),
                event: event,
                kind: item.event.content.isText ? .text : .media,
                heightFingerprint: TimelineRowHeightFingerprint(
                    body: MessageBodyGeometry(variant: item.event.content.isText ? "text" : "image", text: event.body),
                    senderName: item.event.sender.displayName,
                    reactions: ReactionStripGeometry(
                        reactions: item.event.reactions.lazy.map { (key: $0.key, senderCount: $0.count) },
                        hasReadReceipts: false
                    )
                )
            )
        }

        static func eventID(forRowId rowId: String) -> EventID? {
            Int(rowId).map(EventID.init)
        }
    }

    /// The gate's `TimelineFeed` over the spike's `TimelineStore` (MATRIX-87).
    ///
    /// The iOS twin of the Mac gate's `LiveTimeline` stand-in: the display
    /// order and the change queue, computed from the synthetic store. Cost
    /// follows the change, never the timeline. No decoration rows ever
    /// appear: nobody types, pagination never shows activity, and a fetch
    /// cannot fail, so item index equals row index, as on the Mac gate.
    @MainActor @Observable
    final class TimelineGateFeed: TimelineFeed {
        @ObservationIgnored let store: TimelineStore
        @ObservationIgnored private var items: [TimelineRow]
        @ObservationIgnored private var pending: [TimelineRowChange] = []
        /// Bumped on every recorded change; the container tracks it.
        private var generation = 0

        let typingNames: [String] = []
        let isPaginating = false
        let paginationFailure: String? = nil
        private(set) var isAtBottom = true
        let unseenArrivals = 0
        let scrollToBottomRequests = 0

        /// Fetches the container asked for. Every scenario prepends on its own
        /// schedule, as the Mac scenarios do, so a fetch only counts.
        @ObservationIgnored private(set) var fetchRequestCount = 0

        init(store: TimelineStore) {
            self.store = store
            items = store.items.reversed().map(TimelineGateEvent.row(for:))
        }

        /// True until the container has taken every recorded change.
        var hasPendingChanges: Bool { !pending.isEmpty }

        var displayRows: [TimelineRow] { items }

        func drainRowChanges() -> [TimelineRowChange] {
            defer { pending.removeAll(keepingCapacity: true) }
            return pending
        }

        func touchObservedState() {
            _ = generation
        }

        var focusRequestId: String? { nil }

        func itemIndexOfFocusRequest() -> Int? {
            nil
        }

        func setAtBottom(_ atBottom: Bool) {
            guard isAtBottom != atBottom else { return }
            isAtBottom = atBottom
        }

        func requestScrollToBottom() {}

        func fetchOlderMessages() async {
            fetchRequestCount += 1
        }

        func retryPagination() {}

        // MARK: - Store to display order

        /// Records a prepend the store already took: the oldest `count` store
        /// items, which are the newest-first display order's far end.
        func recordPrepend(count: Int) {
            guard count > 0 else { return }
            let batch = store.items.prefix(count).reversed().map(TimelineGateEvent.row(for:))
            let index = items.count
            items.append(contentsOf: batch)
            record(TimelineRowChange(change: .insert(index: index, count: batch.count), rows: batch))
        }

        /// Records mutations the store already applied, one content update
        /// per mutation, as the Mac stand-in does.
        func recordMutations(_ mutations: [Mutation]) {
            for mutation in mutations {
                guard let storeIndex = store.itemIndex(for: mutation.target) else { continue }
                let index = TimelineDisplayOrder.displayIndex(ofSdkIndex: storeIndex, count: items.count)
                guard TimelineDisplayOrder.isValidIndex(index, count: items.count) else { continue }
                let row = TimelineGateEvent.row(for: store.items[storeIndex])
                items[index] = row
                record(TimelineRowChange(change: .update(index: index), rows: [row]))
            }
        }

        private func record(_ change: TimelineRowChange) {
            pending.append(change)
            generation += 1
        }
    }
#endif
