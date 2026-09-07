import AsyncAlgorithms
import Foundation
import MatrixRustSDK
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

    public private(set) var focusedTimelineEventId: EventOrTransactionId?
    // public private(set) var focusedTimelineGroupId: String?

    public var sendReplyTo: MatrixRustSDK.EventTimelineItem?

    public private(set) var timelineItems: [TimelineItem] = []
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
                Logger.liveTimeline.error("failed to configure timeline: \(String(describing: error), privacy: .public)")
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
                Logger.liveTimeline.error("failed to configure timeline: \(String(describing: error), privacy: .public)")
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

    public func focusEvent(id eventId: EventOrTransactionId) {
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

extension LiveTimeline {
    private func updateTimeline(diff: [TimelineDiff]) {
        for update in diff {
            switch update {
            case let .append(values):
                timelineItems.append(contentsOf: values)
                noteArrivals(values)
            case .clear:
                timelineItems.removeAll()
                unseenArrivals = 0
            case let .pushFront(room):
                timelineItems.insert(room, at: 0)
            case let .pushBack(room):
                timelineItems.append(room)
                noteArrivals([room])
            case .popFront:
                timelineItems.removeFirst()
            case .popBack:
                timelineItems.removeLast()
            case let .insert(index, room):
                timelineItems.insert(room, at: Int(index))
            case let .set(index, room):
                timelineItems[Int(index)] = room
            case let .remove(index):
                timelineItems.remove(at: Int(index))
            case let .truncate(length):
                timelineItems.removeSubrange(Int(length) ..< timelineItems.count)
            case let .reset(values: values):
                timelineItems = values
                unseenArrivals = 0
            }
        }

        loadPendingReplyDetails()
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
