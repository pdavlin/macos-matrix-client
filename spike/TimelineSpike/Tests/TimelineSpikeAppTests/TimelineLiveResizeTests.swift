import AppKit
import Foundation
@testable import ProductionTimeline
import Testing
import TimelineSpikeCore

/// MATRIX-197: the production timeline keeps its scroll anchor through a
/// window live resize.
///
/// The controller is the app's own `TimelineViewController`, fed synthetic
/// text events through the spike's `LiveTimeline` bridge, so rows wrap and
/// change height with the width. A test cannot start a real live resize
/// (`inLiveResize` is the window's), so it sends the table the same
/// `viewWillStartLiveResize` and `viewDidEndLiveResize` calls the window
/// sends, and changes the view frame between them.
///
/// The window is borderless and never ordered front.
@MainActor
@Suite("Timeline live resize", .serialized)
struct TimelineLiveResizeTests {
    private static let startSize = NSSize(width: 700, height: 500)

    /// Narrow, then wide, with height changes on the way, as a corner drag
    /// sends them. Each step is one frame of the drag.
    private static let resizeSteps: [NSSize] = [
        NSSize(width: 620, height: 480),
        NSSize(width: 520, height: 460),
        NSSize(width: 420, height: 440),
        NSSize(width: 360, height: 520),
        NSSize(width: 480, height: 560),
        NSSize(width: 700, height: 600),
        NSSize(width: 900, height: 620),
        NSSize(width: 1100, height: 640)
    ]

    @MainActor
    private final class Mounted {
        let harness: SpikeHarness
        let window: NSWindow
        let controller: TimelineViewController

        init(eventCount: Int = 600) {
            _ = NSApplication.shared
            harness = SpikeHarness(
                configuration: HarnessConfiguration(
                    seed: HarnessConfiguration.default.seed,
                    initialEventCount: eventCount,
                    mutation: .default,
                    pagination: PaginationDriverConfiguration(isAutomatic: false)
                )
            )
            controller = TimelineViewController(
                coordinator: TimelineViewRepresentable.Coordinator(appState: AppState(), windowState: WindowState()),
                source: LiveTimeline(harness: harness)
            )
            // Larger than any step, so the window never clips the table's
            // visible rect.
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1400, height: 1000),
                styleMask: [.borderless],
                backing: .buffered,
                defer: true
            )
            window.isReleasedWhenClosed = false
            controller.view.frame = NSRect(origin: .zero, size: TimelineLiveResizeTests.startSize)
            window.contentView?.addSubview(controller.view)
            controller.view.layoutSubtreeIfNeeded()
        }

        var clipView: NSClipView {
            controller.scrollView.contentView
        }

        /// Suspends the test so the main queue runs the deferred re-measures
        /// and scroll reports. A nested run loop would not: the test itself
        /// runs on the main queue, which does not drain inside its own block.
        func settle(_ seconds: Double = 0.02) async throws {
            try await Task.sleep(for: .seconds(seconds))
        }

        /// One frame of the drag: the new frame, its layout, and the
        /// re-measure the controller queues for it.
        func resize(to size: NSSize) async throws {
            controller.view.frame = NSRect(origin: .zero, size: size)
            controller.view.layoutSubtreeIfNeeded()
            try await settle()
        }

        func scroll(toOriginY originY: CGFloat) async throws {
            clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: originY))
            controller.scrollView.reflectScrolledClipView(clipView)
            try await settle()
        }

        /// The visually top-most row on screen: the highest visible index,
        /// because rows run newest-first in an unflipped table.
        var topVisibleRowId: String? {
            let visible = controller.tableView.rows(in: controller.tableView.visibleRect)
            guard visible.length > 0 else { return nil }
            return controller.timelineRows[visible.location + visible.length - 1].uniqueId
        }

        /// A row's top edge below the top of the viewport, in points.
        func distanceFromViewportTop(ofRowId rowId: String) -> CGFloat? {
            guard let row = controller.timelineRows.firstIndex(where: { $0.uniqueId == rowId }) else { return nil }
            let rowRect = controller.tableView.rect(ofRow: row)
            return clipView.bounds.origin.y + clipView.bounds.height - rowRect.maxY
        }

        var isPinnedToBottom: Bool {
            let visible = controller.tableView.rows(in: controller.tableView.visibleRect)
            return clipView.bounds.origin.y <= TimelineViewController.bottomThreshold
                && visible.length > 0 && visible.location == 0
        }

        func close() {
            window.close()
        }
    }

    @Test("A mid-history top row holds its place through a narrow and wide live resize")
    func midHistoryAnchorHolds() async throws {
        let mounted = Mounted()
        defer { mounted.close() }
        // The first layout gives the column its width; the re-measure for it
        // waits out the settle delay.
        try await mounted.settle(0.3)
        // AppKit measures rows lazily and estimates the rest of the document.
        // Measure every row and tile, so the middle of the history stays the
        // middle once the scroll measures the rows around it.
        let tableView = mounted.controller.tableView
        for row in 0 ..< tableView.numberOfRows {
            _ = tableView.rect(ofRow: row)
        }
        tableView.tile()

        let documentHeight = tableView.frame.height
        let viewportHeight = mounted.clipView.bounds.height
        #expect(documentHeight > viewportHeight * 4, "the fixture needs a long history")
        try await mounted.scroll(toOriginY: (documentHeight - viewportHeight) / 2)

        let scrolledOrigin = mounted.clipView.bounds.origin.y
        #expect(scrolledOrigin > documentHeight / 4 && scrolledOrigin < documentHeight * 3 / 4, "the anchor must sit mid-history")

        let anchorId = try #require(mounted.topVisibleRowId)
        let offsetBefore = try #require(mounted.distanceFromViewportTop(ofRowId: anchorId))

        tableView.viewWillStartLiveResize()
        var documentHeights: [CGFloat] = []
        for size in Self.resizeSteps {
            try await mounted.resize(to: size)
            let offset = try #require(mounted.distanceFromViewportTop(ofRowId: anchorId))
            #expect(abs(offset - offsetBefore) <= 1, "at \(size): \(offset) against \(offsetBefore)")
            documentHeights.append(tableView.frame.height)
        }

        tableView.viewDidEndLiveResize()
        let offsetAtEnd = try #require(mounted.distanceFromViewportTop(ofRowId: anchorId))
        #expect(abs(offsetAtEnd - offsetBefore) <= 1, "at the end: \(offsetAtEnd) against \(offsetBefore)")

        // Any deferred re-measure has run by now, and must not move it either.
        try await mounted.settle(0.3)
        let offsetSettled = try #require(mounted.distanceFromViewportTop(ofRowId: anchorId))
        #expect(abs(offsetSettled - offsetBefore) <= 1, "settled: \(offsetSettled) against \(offsetBefore)")

        // The rows did take new heights, so the anchor had work to do: taller
        // on the narrow steps, and a shorter history at the wide end.
        #expect(documentHeights.max() ?? 0 > documentHeight, "the narrow steps must make rows taller")
        #expect(tableView.frame.height < documentHeight, "the wide end must make the history shorter")
    }

    @Test("A timeline pinned to the bottom stays pinned through and after a live resize")
    func bottomPinHolds() async throws {
        let mounted = Mounted()
        defer { mounted.close() }
        try await mounted.settle(0.3)
        #expect(mounted.isPinnedToBottom)

        mounted.controller.tableView.viewWillStartLiveResize()
        for size in Self.resizeSteps {
            try await mounted.resize(to: size)
            #expect(mounted.isPinnedToBottom, "at \(size): origin \(mounted.clipView.bounds.origin.y)")
        }

        mounted.controller.tableView.viewDidEndLiveResize()
        #expect(mounted.isPinnedToBottom)
        try await mounted.settle(0.3)
        #expect(mounted.isPinnedToBottom, "settled: origin \(mounted.clipView.bounds.origin.y)")
    }
}
