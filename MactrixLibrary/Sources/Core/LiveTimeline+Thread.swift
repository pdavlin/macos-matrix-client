import Foundation
import MatrixRustSDK
import Models
import OSLog

/// Two timelines are equal when they show the same room and the same thread
/// (or both the room's main timeline).
extension LiveTimeline: Equatable {
    public nonisolated static func == (lhs: LiveTimeline, rhs: LiveTimeline) -> Bool {
        lhs.room.id == rhs.room.id && lhs.focusedThreadId == rhs.focusedThreadId
    }
}

extension LiveTimeline {
    /// Reads the facts the thread panel shows from the thread timeline's
    /// items (MATRIX-183): the reply count and the root's row identifier. A
    /// no-op for a room timeline.
    ///
    /// The reply count is the root's thread summary count from the SDK. If
    /// the root carries no summary, it is the number of message events in the
    /// timeline other than the root: the replies the panel shows. No Matrix
    /// semantics are derived here; both numbers come from items the SDK gave.
    ///
    /// Cost: one pass over the items, as `loadPendingReplyDetails()` makes,
    /// once per diff batch, and only for a thread timeline.
    func refreshThreadFacts() {
        guard let rootId = focusedThreadId else { return }
        var sawEvent = false
        var loadedReplies = 0
        var summaryCount: Int?
        var rootRowId: String?
        for item in timelineItems {
            guard let event = item.asEvent() else { continue }
            sawEvent = true
            guard case let .msgLike(content: content) = event.content else { continue }
            if event.eventOrTransactionId.id == rootId {
                summaryCount = content.threadSummary.map { Int($0.numReplies()) }
                rootRowId = item.uniqueId().id
            } else {
                loadedReplies += 1
            }
        }
        let facts = ThreadTimelineFacts(
            replyCount: sawEvent ? (summaryCount ?? loadedReplies) : nil,
            rootRowId: rootRowId
        )
        if threadFacts != facts {
            threadFacts = facts
        }
    }
}

// MARK: - Thread fill (MATRIX-229)

extension LiveTimeline {
    /// Loads the whole thread when the panel opens, with no scroll, in at
    /// most `ThreadBackfill.callLimit` calls. See `ThreadBackfill` for why
    /// one call is not enough. A no-op for a room timeline.
    ///
    /// The fill holds the status at `.paginating` from its first call to its
    /// last. A scroll near the top then does not start a second pagination,
    /// and the activity row shows once for the whole fill, not once per call.
    /// The calls hold the timeline weakly, so a closed panel stops the fill
    /// at its next call.
    func startThreadFill() {
        guard focusedThreadId != nil, paginationFailure == nil,
              paginating == .idle(hitTimelineStart: false) else { return }

        Logger.liveTimeline.info("thread fill: start, at most \(ThreadBackfill.callLimit) call(s)")
        paginating = .paginating
        Task { [weak self] in
            let outcome = await ThreadBackfill.run(
                paginateOnce: { [weak self] call in
                    guard let timeline = self?.timeline else { throw CancellationError() }
                    do {
                        let hitStart = try await timeline.paginateBackwards(numEvents: 100)
                        let items = self?.timelineItems.count ?? 0
                        Logger.liveTimeline.info(
                            "thread fill: call \(call) done, thread start: \(hitStart), \(items) item(s)"
                        )
                        return hitStart
                    } catch {
                        Logger.liveTimeline.error(
                            "thread fill: call \(call) failed: \(String(describing: error), privacy: .public)"
                        )
                        throw error
                    }
                },
                pause: { try await Task.sleep(for: ThreadBackfill.pause) }
            )
            self?.finishThreadFill(outcome)
        }
    }

    private func finishThreadFill(_ outcome: ThreadBackfill.Outcome) {
        let items = timelineItems.count
        switch outcome {
        case let .reachedStart(calls):
            Logger.liveTimeline.info("thread fill: reached the thread start after \(calls) call(s), \(items) item(s)")
            paginating = .idle(hitTimelineStart: true)
        case let .callLimit(calls):
            Logger.liveTimeline.info(
                "thread fill: stopped at the limit of \(calls) call(s), \(items) item(s); a scroll near the top loads more"
            )
            paginating = .idle(hitTimelineStart: false)
        case let .failed(calls, message):
            Logger.liveTimeline.error("thread fill: stopped by a failure at call \(calls), \(items) item(s)")
            paginationFailure = message
            paginating = .idle(hitTimelineStart: false)
        }
    }
}
