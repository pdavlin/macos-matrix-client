import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The thread timelines a main timeline's composer sent to, and the local
/// echoes in them that are not sent (MATRIX-173).
///
/// A reply to a thread from the main composer goes out through a timeline
/// with the focus on that thread (`LiveTimeline.sdkTimeline(for:)`), and the
/// main timeline hides threaded events. This class keeps each such thread
/// timeline, listens to it, and publishes its unsent echoes, so the main
/// column can show `Models.ThreadReplyNotice`.
///
/// The SDK owns the send queue. This class reads the send state the thread
/// timeline reports, and Retry and Discard use the same send-queue calls as
/// a failed row of the timeline (`ChatMessageView.retrySend`).
///
/// A thread timeline stays here for the life of the main timeline. The count
/// is the number of threads the user answered from the main composer.
@MainActor @Observable
public final class ThreadReplyWatch {
    private struct WatchedThread {
        let timeline: Timeline
        let handle: TaskHandle
        var items: [TimelineItem] = []
    }

    @ObservationIgnored private let room: LiveRoom
    @ObservationIgnored private var threads: [String: WatchedThread] = [:]

    /// The local echoes that are not sent, in the order of the thread roots
    /// and then of the thread timelines.
    public private(set) var echoes: [ThreadReplyEcho] = []

    /// False if the room's send queue is stopped. Read from the SDK each
    /// time the echoes are read.
    public private(set) var isSendQueueEnabled = true

    init(room: LiveRoom) {
        self.room = room
    }

    /// The SDK timeline with the focus on the thread of `root`. The first
    /// call for a thread makes the timeline and starts the listener.
    func timeline(forThread root: String) async throws -> Timeline {
        if let watched = threads[root] {
            return watched.timeline
        }
        let timeline = try await room.room.timelineWithConfiguration(
            configuration: LiveTimeline.configuration(focus: .thread(rootEventId: root))
        )
        let listener = AsyncSDKListener<[TimelineDiff]>()
        let handle = await timeline.addListener(listener: listener)
        // A second send to the same thread made the timeline during the
        // calls above: keep that one, and release this one.
        if let watched = threads[root] {
            return watched.timeline
        }
        threads[root] = WatchedThread(timeline: timeline, handle: handle)
        Task { [weak self] in
            for await diffs in listener {
                guard let self else { break }
                apply(diffs, toThread: root)
            }
        }
        return timeline
    }

    /// Reads the unsent echoes and the state of the send queue again. The
    /// main timeline calls it on each of its updates, because a failure of a
    /// message there can stop the queue with no change in a thread timeline.
    func refresh() {
        guard !threads.isEmpty else { return }
        var found: [ThreadReplyEcho] = []
        for root in threads.keys.sorted() {
            for item in threads[root]?.items ?? [] {
                guard let event = item.asEvent(), let state = event.sendState, state != .sent else { continue }
                found.append(ThreadReplyEcho(threadRoot: root, itemId: event.eventOrTransactionId.id, sendState: state))
            }
        }
        // Write only a change, so an update with no change does not
        // invalidate the views that read these.
        if found != echoes {
            echoes = found
        }
        let enabled = room.room.isSendQueueEnabled()
        if enabled != isSendQueueEnabled {
            isSendQueueEnabled = enabled
        }
    }

    /// Retry of the notice. A recoverable failure stopped the room's send
    /// queue, so the retry starts it and the queue sends on its own. An
    /// unrecoverable failure wedged the echo, so the retry sends it again
    /// through its send handle.
    public func retry(_ notice: ThreadReplyNotice) async {
        switch notice.retry {
        case .enableSendQueue:
            room.room.enableSendQueue(enable: true)
            Logger.liveTimeline.info("re-enabled send queue to retry thread reply \(notice.itemId)")
            refresh()
        case .resend:
            guard let handle = sendHandle(of: notice) else { return }
            do {
                try await handle.tryResend()
                Logger.liveTimeline.info("resend requested for thread reply \(notice.itemId)")
            } catch {
                Logger.liveTimeline.error("failed to resend thread reply \(notice.itemId): \(error)")
            }
        }
    }

    /// Discard of the notice: aborts the echo in the send queue.
    public func discard(_ notice: ThreadReplyNotice) async {
        guard let handle = sendHandle(of: notice) else { return }
        do {
            let aborted = try await handle.abort()
            Logger.liveTimeline.info("abort of thread reply \(notice.itemId) returned \(aborted)")
        } catch {
            Logger.liveTimeline.error("failed to abort thread reply \(notice.itemId): \(error)")
        }
    }

    private func sendHandle(of notice: ThreadReplyNotice) -> SendHandle? {
        let event = threads[notice.threadRoot]?.items.lazy
            .compactMap { $0.asEvent() }
            .first { $0.eventOrTransactionId.id == notice.itemId }
        guard let handle = event?.lazyProvider.getSendHandle() else {
            Logger.liveTimeline.error("no send handle for thread reply \(notice.itemId)")
            return nil
        }
        return handle
    }

    private func apply(_ diffs: [TimelineDiff], toThread root: String) {
        guard var items = threads[root]?.items else { return }
        for diff in diffs {
            Self.apply(diff, to: &items)
        }
        threads[root]?.items = items
        refresh()
    }

    /// Applies one SDK diff to the items of a thread timeline. A diff with
    /// an index outside the items is dropped; the SDK does not send one.
    private static func apply(_ diff: TimelineDiff, to items: inout [TimelineItem]) {
        switch diff {
        case let .append(values):
            items.append(contentsOf: values)
        case .clear:
            items.removeAll()
        case let .pushFront(item):
            items.insert(item, at: 0)
        case let .pushBack(item):
            items.append(item)
        case .popFront:
            guard !items.isEmpty else { return }
            items.removeFirst()
        case .popBack:
            guard !items.isEmpty else { return }
            items.removeLast()
        case let .insert(index, item):
            guard Int(index) <= items.count else { return }
            items.insert(item, at: Int(index))
        case let .set(index, item):
            guard Int(index) < items.count else { return }
            items[Int(index)] = item
        case let .remove(index):
            guard Int(index) < items.count else { return }
            items.remove(at: Int(index))
        case let .truncate(length):
            guard Int(length) < items.count else { return }
            items.removeSubrange(Int(length) ..< items.count)
        case let .reset(values: values):
            items = values
        }
    }
}
