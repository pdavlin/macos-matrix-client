import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
import Tokens
@testable import UI

/// MATRIX-142: the merged timeline's source note, light and dark, and its
/// fixed height.
///
/// Same capture as `TimelineDecorationSnapshotTests`: a fixed 2x scale and a
/// pinned appearance. The snapshots are the local and agent-side gate
/// (contract R-8); the height checks also run on CI, because they do not
/// depend on font rasterization.
@MainActor
struct MergedSourceNoteSnapshotTests {
    private func host(
        _ view: some View,
        width: CGFloat = 420,
        appearance: NSAppearance.Name = .aqua
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not follow the system's.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    private static let slackNote = MergedSourceNote(network: .slack, title: "Slack", detail: "DevObsessed")

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func networkAndDetailLight() {
        assertSnapshot(of: host(Self.slackNote), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func networkAndDetailDark() {
        assertSnapshot(of: host(Self.slackNote, appearance: .darkAqua), as: .scaledImage)
    }

    /// No known network: no badge, the room's name only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func titleOnlyLight() {
        assertSnapshot(of: host(MergedSourceNote(network: nil, title: "Seth")), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func titleOnlyDark() {
        assertSnapshot(of: host(MergedSourceNote(network: nil, title: "Seth"), appearance: .darkAqua), as: .scaledImage)
    }

    /// A label wider than the row truncates on one line.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func longLabelTruncatesLight() {
        let note = MergedSourceNote(network: .googleChat, title: "Google Chat", detail: "pizza box audit committee and friends")
        assertSnapshot(of: host(note, width: 200), as: .scaledImage)
    }

    /// MATRIX-142 Phase B: the timeline draws the note as a virtual row, and
    /// the row measurement skips that row at `MergedSourceLabel.rowHeight`
    /// (Models). The constant, the token, and the drawn row must agree.
    @Test(arguments: [80, 420] as [CGFloat])
    func virtualRowHasTheFixedRowHeight(width: CGFloat) {
        let label = MergedSourceLabel(roomId: "!a:davlin.io", network: .slack, roomName: "Seth")
        let row = TimelineRow.virtual(uniqueId: "merged:source:!a:davlin.io|1", item: .mergedSource(label))

        #expect(MergedSourceLabel.rowHeight == MergedSourceNoteToken.height)
        #expect(row.fixedHeight == MergedSourceNoteToken.height)
        #expect(host(VirtualItemView(item: .mergedSource(label)), width: width).view.fittingSize.height == MergedSourceNoteToken.height)
    }

    /// The row measurement relies on one height at every width, with or
    /// without a badge, and for a label too long for the row.
    @Test(arguments: [80, 200, 420, 900] as [CGFloat])
    func heightIsFixedAtEveryWidth(width: CGFloat) {
        let notes = [
            Self.slackNote,
            MergedSourceNote(network: nil, title: "Seth"),
            MergedSourceNote(network: .googleChat, title: "Google Chat", detail: String(repeating: "pizza box audit ", count: 20)),
        ]
        for note in notes {
            #expect(host(note, width: width).view.fittingSize.height == MergedSourceNoteToken.height)
        }
    }
}
