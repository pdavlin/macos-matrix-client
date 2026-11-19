import Core
import Models

/// A thread timeline as the timeline container's row source (MATRIX-183):
/// the thread's own rows, plus the "N replies" divider right after the root.
///
/// The divider has no SDK item, so the rows go through `ThreadTimelineRows`,
/// which mirrors the thread's changes and states the difference with the
/// divider in place. Everything else is the thread timeline's own: actions,
/// typing, pagination, scroll, and focus.
@MainActor
final class ThreadTimelineRowSource: TimelineRowSource {
    let timeline: LiveTimeline
    private var rows = ThreadTimelineRows()

    /// Cheap: the representable can make one on each view update, and only
    /// the first one reaches the controller.
    init(timeline: LiveTimeline) {
        self.timeline = timeline
    }

    // MARK: Rows

    /// Starts again from the thread's whole row list. The container reads it
    /// on the first load and on a reset; both times it holds no change of
    /// the thread that is not drained yet.
    var displayRows: [TimelineRow] {
        rows.start(base: timeline.displayRows, anchor: timeline.threadFacts.dividerAnchor)
    }

    func drainRowUpdates() -> [TimelineRowDisplayUpdate] {
        rows.apply(timeline.drainRowUpdates(), anchor: timeline.threadFacts.dividerAnchor)
    }

    func discardRowUpdates() {
        timeline.discardRowUpdates()
    }

    // MARK: Rooms

    func timeline(for _: TimelineRow) -> LiveTimeline? {
        timeline
    }

    var actionTimelines: [LiveTimeline] {
        [timeline]
    }

    // MARK: Decorations

    var typingNames: [String] {
        timeline.typingNames
    }

    var isPaginating: Bool {
        timeline.isPaginating
    }

    var paginationFailure: String? {
        timeline.paginationFailure
    }

    // MARK: Scroll

    var scrollToBottomRequests: Int {
        timeline.scrollToBottomRequests
    }

    func setAtBottom(_ atBottom: Bool) {
        timeline.setAtBottom(atBottom)
    }

    func paginateBackwards() async {
        await timeline.paginateBackwards()
    }

    // MARK: Focus

    var focusTarget: TimelineEventReference? {
        timeline.focusTarget
    }

    func rowId(of event: TimelineEventReference) -> String? {
        timeline.rowId(of: event)
    }
}
