import Models
import Observation
import OSLog
import SwiftUI
import UI

// The app-target symbols the production container names, declared here so the
// symlinked container files compile inside the spike package. Every type in
// this file is a stand-in for something in `Mactrix/`, and each one exists
// because the container mentions it — not because the measurement needs it.

/// Stand-in for the app's global state object.
///
/// The container reaches it only to hand row views an `ImageLoader`. Synthetic
/// rows carry no avatar URLs, so the loader is absent and every avatar draws
/// its placeholder — the same branch a real timeline takes before an avatar
/// has downloaded.
@MainActor
@Observable
final class AppState {
    var matrixClient: ImageLoader?

    init() {}
}

/// Stand-in for the per-window state object. Thread focus is the only thing
/// the timeline rows ask of it, and no synthetic row has a thread.
@MainActor
@Observable
final class WindowState {
    func focusThread(rootEventId: String) {
        Logger.timelineTableView.debug("thread focus ignored in the harness: \(rootEventId, privacy: .public)")
    }
}

/// Stand-in for the app's `NSViewControllerRepresentable`.
///
/// Only the nested coordinator reaches the container, and only as the carrier
/// of the two environment objects, so the outer type is a namespace.
enum TimelineViewRepresentable {
    @MainActor
    final class Coordinator {
        let appState: AppState
        let windowState: WindowState

        init(appState: AppState, windowState: WindowState) {
            self.appState = appState
            self.windowState = windowState
        }
    }
}

extension Logger {
    private static let subsystem = "dev.mactrix.timeline-spike"

    static let timelineTableView = Logger(subsystem: subsystem, category: "timeline-table-view")
    static let timelineRowMapping = Logger(subsystem: subsystem, category: "timeline-row-mapping")
    static let viewCycle = Logger(subsystem: subsystem, category: "viewcycle")
}
