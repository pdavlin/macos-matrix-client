import Core
import MatrixRustSDK
import Models
import SwiftUI

struct TimelineViewRepresentable: NSViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let source: any TimelineRowSource
    /// The observation dependency of a room timeline: the parent reads
    /// `timelineItems` to build it. Empty for a merged chat.
    private let items: [TimelineItem]
    /// The observation dependency of a merged chat (MATRIX-142): the parent
    /// reads `rows` to build it. Empty for a room timeline.
    private let rows: [TimelineRow]
    /// The height of the composer that floats over the bottom of the
    /// timeline: the scroll view's bottom content inset (MATRIX-198).
    private let bottomInset: CGFloat

    /// One room's timeline, or a thread's: a thread timeline gets the
    /// "N replies" divider after its root (MATRIX-183). The controller keeps
    /// the source it was made with, so a new thread needs a new view
    /// identity (`InspectorScreen` gives one per thread timeline).
    init(timeline: LiveTimeline, items: [TimelineItem], bottomInset: CGFloat = 0) {
        self.source = timeline.focusedThreadId == nil ? timeline : ThreadTimelineRowSource(timeline: timeline)
        self.items = items
        self.rows = []
        self.bottomInset = bottomInset
    }

    /// A merged chat's timeline (MATRIX-142 Wave 2). Give the view an
    /// identity per `MergedLiveTimeline` instance (`.id`), because the
    /// controller keeps the source it was made with.
    init(merged: MergedLiveTimeline, rows: [TimelineRow], bottomInset: CGFloat = 0) {
        self.source = merged
        self.items = []
        self.rows = rows
        self.bottomInset = bottomInset
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(appState: appState, windowState: windowState)
    }

    class Coordinator {
        let appState: AppState
        let windowState: WindowState

        init(appState: AppState, windowState: WindowState) {
            self.appState = appState
            self.windowState = windowState
        }
    }

    func makeNSViewController(context: Context) -> TimelineViewController {
        return TimelineViewController(coordinator: context.coordinator, source: source)
    }

    /// `items` and `rows` are the observation dependency that brings SwiftUI
    /// here; the controller reads the display order and the change queue
    /// from the source itself, so it never rebuilds from the array (S-34).
    func updateNSViewController(_ timelineViewController: TimelineViewController, context _: Context) {
        timelineViewController.setBottomContentInset(bottomInset)
        timelineViewController.applyPendingTimelineChanges()
    }
}
