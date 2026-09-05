import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import Models
import OSLog
import SwiftUI

@MainActor @Observable
public final class LiveTimeline {
    public let room: LiveRoom
    public let focusedThreadId: String?

    public var timeline: Timeline?

    @ObservationIgnored private var timelineHandle: TaskHandle?
    @ObservationIgnored private var paginateHandle: TaskHandle?

    public var scrollPosition = ScrollPosition(idType: TimelineGroup.ID.self, edge: .bottom)
    public var errorMessage: String?

    public private(set) var focusedTimelineEventId: MatrixRustSDK.EventOrTransactionId?
    // public private(set) var focusedTimelineGroupId: String?

    public var sendReplyTo: MatrixRustSDK.EventTimelineItem?

    public private(set) var timelineItems: [TimelineItem] = []

    /// The same items in display order, newest first — the order the timeline
    /// container renders and the order the SDK does not provide.
    ///
    /// Maintained by mirroring every diff onto both arrays (S-34). The
    /// container used to reverse `timelineItems` on each update, which cost a
    /// full copy per update no matter how small the change.
    public private(set) var displayItems: [TimelineItem] = []

    /// Display-ordered changes the container has not consumed yet.
    ///
    /// Deliberately not observable. The container drains this from inside
    /// SwiftUI's view update pass, and an observable write there is the
    /// re-entrancy the S-54 fix exists to avoid. Publication is driven by
    /// `timelineItems`/`displayItems` instead.
    @ObservationIgnored private var pendingDisplayChanges: [TimelineDisplayUpdate] = []

    public private(set) var loadedReplyDetails: [String: InReplyToDetails] = [:]
    // public private(set) var timelineGroups: TimelineGroups = .init()

    public private(set) var paginating: PaginationStatus = .idle(hitTimelineStart: false)
    public private(set) var hitTimelineStart: Bool = false

    /// Whether the timeline view is scrolled to (or near) the newest message.
    /// Written by the timeline container on scroll; read by the
    /// scroll-to-bottom affordance.
    public private(set) var isAtBottom: Bool = true

    /// Messages from other senders that arrived while the view was scrolled
    /// away from the bottom. Cleared when the view returns to the bottom.
    public private(set) var unseenArrivals: Int = 0

    /// Monotonic counter the timeline container observes; each increment is
    /// one scroll-to-bottom request.
    public private(set) var scrollToBottomRequests: Int = 0

    public init(room: LiveRoom) {
        self.focusedThreadId = nil
        self.room = room
        Task {
            do {
                try await configureTimeline()
            } catch {
                Logger.liveTimeline.error("failed to configure timeline: \(error)")
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public init(room: LiveRoom, focusThread threadId: String) {
        self.focusedThreadId = threadId
        self.room = room
        Task {
            do {
                try await configureTimeline(threadId: threadId)
            } catch {
                Logger.liveTimeline.error("failed to configure timeline: \(error)")
                self.errorMessage = error.localizedDescription
            }
        }
    }

    deinit {
        Logger.liveTimeline.debug("Timeline deinit")
    }

    private func configureTimeline(threadId: String? = nil) async throws {
        Logger.liveTimeline.debug("configure timeline")

        let focus = if let threadId {
            TimelineFocus.thread(rootEventId: threadId)
        } else {
            TimelineFocus.live(hideThreadedEvents: true)
        }

        let config = TimelineConfiguration(
            focus: focus,
            filter: .all,
            internalIdPrefix: nil,
            dateDividerMode: .daily,
            trackReadReceipts: .allEvents,
            // Forward this timeline's UTDs to the client's delegate
            // (`UtdReporter`), so a failure to decrypt is recorded with the
            // cause the crypto layer assigns it instead of being silent.
            reportUtds: true
        )
        timeline = try await room.room.timelineWithConfiguration(configuration: config)

        await listenToTimelineChanges()

        do {
            try await listenToPaginationStatus(threadId: threadId)
        } catch {
            Logger.liveTimeline.error("Failed to listen to pagination status: \(error)")
        }
    }

    private func listenToTimelineChanges() async {
        guard let timeline else { return }

        let listener = AsyncSDKListener<[TimelineDiff]>()
        timelineHandle = await timeline.addListener(listener: listener)

        Task { [weak self] in
            for await diff in listener {
                guard let self else { break }
                updateTimeline(diff: diff)
            }
        }
    }

    private func listenToPaginationStatus(threadId: String?) async throws {
        guard let timeline else { return }

        let listener = AsyncSDKListener<PaginationStatus>()
        // Only main timelines can subscibe to back pagination status
        if threadId == nil {
            paginateHandle = try await timeline.subscribeToBackPaginationStatus(listener: listener)
        } else {
            // if in a thread, instead push one initial status manually to kick off message fetching
            listener.publishValue(.idle(hitTimelineStart: false))
        }

        Task { [weak self] in
            for await status in listener {
                guard let self else { break }

                Logger.liveTimeline.debug("updating timeline paginating: \(status.debugDescription)")
                paginating = status

                if paginating == .idle(hitTimelineStart: false), timelineItems.count < 20 {
                    try await Task.sleep(for: .milliseconds(500))
                    try await fetchOlderMessages()
                }
            }
        }
    }

    public func fetchOlderMessages() async throws {
        guard paginating == .idle(hitTimelineStart: false) else {
            let p = paginating.debugDescription
            Logger.liveTimeline.debug("fetchOlderMessages cancelled, paginating was \(p)")
            return
        }

        Logger.liveTimeline.info("fetch more messages")
        _ = try await timeline?.paginateBackwards(numEvents: 100)
    }

    public func focusEvent(id eventId: MatrixRustSDK.EventOrTransactionId) {
        Logger.liveTimeline.info("focus event: \(eventId.id)")
        focusedTimelineEventId = eventId
    }

    /// Called by the timeline container as the scroll position crosses the
    /// bottom threshold. Reaching the bottom clears the unseen counter.
    public func setAtBottom(_ atBottom: Bool) {
        guard isAtBottom != atBottom else { return }
        isAtBottom = atBottom
        if atBottom {
            unseenArrivals = 0
        }
    }

    /// Asks the timeline container to scroll to the newest message.
    public func requestScrollToBottom() {
        scrollToBottomRequests += 1
        setAtBottom(true)
    }
}

/// A display-ordered change together with the items it introduced.
///
/// The change alone is not enough to replay a batch: several diffs can land
/// between two view updates, and by then the array indices in an earlier
/// change no longer address the items that change inserted. Carrying the
/// payload keeps every entry self-contained.
struct TimelineDisplayUpdate {
    let change: TimelineDisplayChange
    /// Inserted or replacement items, in display order. Empty for removals
    /// and resets.
    let items: [TimelineItem]
}

extension LiveTimeline {
    /// Hands the container every display-ordered change since its last call,
    /// and clears the queue.
    ///
    /// Several diffs can land between two SwiftUI view updates, so the
    /// container consumes a batch rather than one change. A caller that has
    /// never drained gets the whole history, which is why a fresh container
    /// rebuilds from `displayItems` and drains before its first update.
    func drainDisplayChanges() -> [TimelineDisplayUpdate] {
        defer { pendingDisplayChanges.removeAll(keepingCapacity: true) }
        return pendingDisplayChanges
    }

    /// Drops queued changes and forces the next consumer to rebuild.
    func invalidateDisplayChanges() {
        pendingDisplayChanges = [TimelineDisplayUpdate(change: .reset, items: [])]
    }

    private func updateTimeline(diff: [TimelineDiff]) {
        for update in diff {
            apply(update)
        }

        // One O(1) guard against the two arrays drifting apart. Index math is
        // easy to get wrong in one direction only, and a silent drift would
        // render the wrong row for every later index; a resync costs one
        // rebuild and is always correct.
        if displayItems.count != timelineItems.count {
            Logger.liveTimeline.error(
                "display order desynchronized (\(self.displayItems.count) vs \(self.timelineItems.count)): resyncing"
            )
            resyncDisplayItems()
        }

        loadPendingReplyDetails()
    }

    /// Applies one SDK diff to the SDK-ordered array and mirrors it onto the
    /// display-ordered array, recording the display-index change the
    /// container replays.
    private func apply(_ update: TimelineDiff) {
        switch update {
        case let .append(values):
            timelineItems.append(contentsOf: values)
            // Appending at the newest end is a prepend in display order.
            displayItems.insert(contentsOf: values.reversed(), at: 0)
            record(.insert(index: 0, count: values.count), items: values.reversed())
            noteArrivals(values)
        case .clear:
            timelineItems.removeAll()
            displayItems.removeAll()
            record(.reset)
            unseenArrivals = 0
        case let .pushFront(room):
            timelineItems.insert(room, at: 0)
            displayItems.append(room)
            record(.insert(index: displayItems.count - 1, count: 1), items: [room])
        case let .pushBack(room):
            timelineItems.append(room)
            displayItems.insert(room, at: 0)
            record(.insert(index: 0, count: 1), items: [room])
            noteArrivals([room])
        case .popFront:
            guard !timelineItems.isEmpty, !displayItems.isEmpty else { return resyncDisplayItems() }
            timelineItems.removeFirst()
            displayItems.removeLast()
            record(.remove(index: displayItems.count, count: 1))
        case .popBack:
            guard !timelineItems.isEmpty, !displayItems.isEmpty else { return resyncDisplayItems() }
            timelineItems.removeLast()
            displayItems.removeFirst()
            record(.remove(index: 0, count: 1))
        case let .insert(index, room):
            let displayIndex = TimelineDisplayOrder.displayInsertIndex(
                ofSdkIndex: Int(index),
                countBeforeInsert: displayItems.count
            )
            guard TimelineDisplayOrder.isValidInsertIndex(Int(index), count: timelineItems.count),
                  TimelineDisplayOrder.isValidInsertIndex(displayIndex, count: displayItems.count)
            else { return resyncDisplayItems() }
            timelineItems.insert(room, at: Int(index))
            displayItems.insert(room, at: displayIndex)
            record(.insert(index: displayIndex, count: 1), items: [room])
        case let .set(index, room):
            let displayIndex = TimelineDisplayOrder.displayIndex(ofSdkIndex: Int(index), count: displayItems.count)
            guard TimelineDisplayOrder.isValidIndex(Int(index), count: timelineItems.count),
                  TimelineDisplayOrder.isValidIndex(displayIndex, count: displayItems.count)
            else { return resyncDisplayItems() }
            timelineItems[Int(index)] = room
            displayItems[displayIndex] = room
            record(.update(index: displayIndex), items: [room])
        case let .remove(index):
            let displayIndex = TimelineDisplayOrder.displayIndex(ofSdkIndex: Int(index), count: displayItems.count)
            guard TimelineDisplayOrder.isValidIndex(Int(index), count: timelineItems.count),
                  TimelineDisplayOrder.isValidIndex(displayIndex, count: displayItems.count)
            else { return resyncDisplayItems() }
            timelineItems.remove(at: Int(index))
            displayItems.remove(at: displayIndex)
            record(.remove(index: displayIndex, count: 1))
        case let .truncate(length):
            // The SDK keeps the oldest `length` items, so the removal lands at
            // the newest end — the front of the display order.
            let removed = timelineItems.count - Int(length)
            guard removed > 0, Int(length) >= 0, removed <= displayItems.count else { return resyncDisplayItems() }
            timelineItems.removeSubrange(Int(length) ..< timelineItems.count)
            displayItems.removeFirst(removed)
            record(.remove(index: 0, count: removed))
        case let .reset(values: values):
            timelineItems = values
            displayItems = values.reversed()
            record(.reset)
            unseenArrivals = 0
        }
    }

    private func record(_ change: TimelineDisplayChange, items: [TimelineItem] = []) {
        let update = TimelineDisplayUpdate(change: change, items: items)
        if case .reset = change {
            // A reset supersedes everything queued before it.
            pendingDisplayChanges = [update]
        } else {
            pendingDisplayChanges.append(update)
        }
    }

    /// Rebuilds the display order from the SDK order and tells the container
    /// to start over. Used when a diff index does not match local state.
    private func resyncDisplayItems() {
        displayItems = timelineItems.reversed()
        record(.reset)
    }

    /// Counts message events from other senders that arrive at the newest end
    /// while the view is scrolled away from the bottom, feeding the unread
    /// chip. Own messages are excluded: sending already scrolls to bottom.
    private func noteArrivals(_ items: [TimelineItem]) {
        guard !isAtBottom else { return }
        let newMessages = items.count(where: { item in
            guard let event = item.asEvent(), case .msgLike = event.content else { return false }
            return !event.isOwn
        })
        if newMessages > 0 {
            unseenArrivals += newMessages
        }
    }

    private func loadPendingReplyDetails() {
        guard let sdkTimeline = timeline else { return }
        for item in timelineItems {
            guard let event = item.asEvent() else { continue }
            guard case let .msgLike(content: msgLike) = event.content else { continue }
            guard let inReplyTo = msgLike.inReplyTo else { continue }
            let eventId = inReplyTo.eventId()
            switch inReplyTo.event() {
            case .ready, .error: continue
            case .pending, .unavailable: break
            }
            guard loadedReplyDetails[eventId] == nil else { continue }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let details = try await sdkTimeline.loadReplyDetails(eventIdStr: eventId)
                    self.loadedReplyDetails[eventId] = details
                } catch {
                    Logger.liveTimeline.error("loadPendingReplyDetails: failed \(eventId): \(error)")
                }
            }
        }
    }
}

extension LiveTimeline: Equatable {
    public nonisolated static func == (lhs: LiveTimeline, rhs: LiveTimeline) -> Bool {
        lhs.room.id == rhs.room.id && lhs.focusedThreadId == rhs.focusedThreadId
    }
}
