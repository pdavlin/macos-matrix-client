import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-209: the edit history popover's content, and the "(edited)" mark
/// that opens it.
///
/// The bodies are plain `Text`: the app draws them with the timeline's text
/// rendering, which has snapshots of its own. Times are fixed text.
/// References render at a fixed 2x through `.scaledImage` with the light
/// appearance pinned (contract R-8).
@MainActor
struct EditHistorySnapshotTests {
    private typealias Version = EditHistoryVersion<String>

    private func snapshot(of view: some View) -> NSHostingController<AnyView> {
        let controller = NSHostingController(rootView: AnyView(view.background(Color(NSColor.controlBackgroundColor))))
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private func history(_ state: EditHistoryState<String>) -> some View {
        EditHistoryView(
            state: state,
            timeText: { _ in "Nov 19, 2026 at 9:41 AM" },
            messageBody: { text in Text(text).fixedSize(horizontal: false, vertical: true) }
        )
    }

    /// Newest first: an edit, a version that does not decrypt, and the
    /// original with its mark. The long version wraps.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func versionsNewestFirstWithTheOriginalMarked() {
        let versions = Version.newestFirst([
            (body: .message("The meeting is on Wednesday."), timestamp: 1_000),
            (body: .unableToDecrypt(.unknown), timestamp: 2_000),
            (
                body: .message("The meeting moved to Thursday at ten, in the large room on the second floor. Bring last week's notes."),
                timestamp: 3_000
            ),
        ])
        assertSnapshot(of: snapshot(of: history(.loaded(versions))), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func loadFailure() {
        assertSnapshot(of: snapshot(of: history(.failed)), as: .scaledImage)
    }

    /// Many versions: the list stops at its maximum height and scrolls.
    @Test func longHistoryStopsAtTheMaximumHeight() {
        let versions = Version.newestFirst((0 ..< 40).map { (body: .message("Version \($0)"), timestamp: UInt64($0) * 1_000) })
        let short = snapshot(of: history(.loaded(Version.newestFirst([(body: .message("Only"), timestamp: 0)])))).view.fittingSize
        let long = snapshot(of: history(.loaded(versions))).view.fittingSize
        #expect(long.width == EditHistoryView<String, Text>.width)
        #expect(long.height > short.height)
        #expect(long.height <= EditHistoryView<String, Text>.maxListHeight + 60)
    }

    /// The clickable mark keeps the size of the plain mark, so an edited row
    /// measures the same either way.
    @Test func clickableEditedMarkKeepsItsSize() {
        let plain = snapshot(of: EditedMarker()).view.fittingSize
        let clickable = snapshot(of: EditedMarker(showHistory: {})).view.fittingSize
        #expect(plain == clickable)
    }
}
