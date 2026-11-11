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

    /// One room's timeline.
    init(timeline: LiveTimeline, items: [TimelineItem]) {
        self.source = timeline
        self.items = items
        self.rows = []
    }

    /// A merged chat's timeline (MATRIX-142 Wave 2). Give the view an
    /// identity per `MergedLiveTimeline` instance (`.id`), because the
    /// controller keeps the source it was made with.
    init(merged: MergedLiveTimeline, rows: [TimelineRow]) {
        self.source = merged
        self.items = []
        self.rows = rows
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
        timelineViewController.applyPendingTimelineChanges()
    }
}
