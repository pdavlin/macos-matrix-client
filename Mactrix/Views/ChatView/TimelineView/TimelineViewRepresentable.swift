import MatrixRustSDK
import SwiftUI

struct TimelineViewRepresentable: NSViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let timeline: LiveTimeline
    let items: [TimelineItem]

    init(timeline: LiveTimeline, items: [TimelineItem]) {
        self.timeline = timeline
        self.items = items
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
        return TimelineViewController(coordinator: context.coordinator, timeline: timeline)
    }

    /// `items` is the observation dependency that brings SwiftUI here; the
    /// controller reads the display order and the change queue from the
    /// timeline itself, so it never rebuilds from the array (S-34).
    func updateNSViewController(_ timelineViewController: TimelineViewController, context _: Context) {
        timelineViewController.applyPendingTimelineChanges()
    }
}
