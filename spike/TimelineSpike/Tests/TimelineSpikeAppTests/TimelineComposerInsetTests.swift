import AppKit
import Foundation
@testable import ProductionTimeline
import Testing
import TimelineSpikeCore

/// The production controller in a borderless window, never ordered front.
@MainActor
private final class ComposerInsetMount {
    static let viewportSize = NSSize(width: 700, height: 500)

    let harness: SpikeHarness
    let window: NSWindow
    let source: LiveTimeline
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
        source = LiveTimeline(harness: harness)
        controller = TimelineViewController(
            coordinator: TimelineViewRepresentable.Coordinator(appState: AppState(), windowState: WindowState()),
            source: source
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 1000),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        controller.view.frame = NSRect(origin: .zero, size: ComposerInsetMount.viewportSize)
        window.contentView?.addSubview(controller.view)
        controller.view.layoutSubtreeIfNeeded()
    }

    var clipView: NSClipView {
        controller.scrollView.contentView
    }

    var originY: CGFloat {
        clipView.bounds.origin.y
    }

    /// The top of the band the composer covers, in table coordinates.
    var composerTop: CGFloat {
        clipView.bounds.minY + controller.scrollView.contentInsets.bottom
    }

    /// Suspends the test so the main queue runs the deferred reports.
    func settle(_ seconds: Double = 0.02) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    func setInset(_ inset: CGFloat) async throws {
        controller.setBottomContentInset(inset)
        try await settle()
    }

    func scroll(toOriginY originY: CGFloat) async throws {
        clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: originY))
        controller.scrollView.reflectScrolledClipView(clipView)
        try await settle()
    }

    /// Measures every row and tiles, so the document height is exact.
    func measureAllRows() {
        let tableView = controller.tableView
        for row in 0 ..< tableView.numberOfRows {
            _ = tableView.rect(ofRow: row)
        }
        tableView.tile()
    }

    /// The newest row's bottom edge (unflipped: its `minY`), in table
    /// coordinates.
    var newestRowBottom: CGFloat {
        controller.tableView.rect(ofRow: 0).minY
    }

    func close() {
        window.close()
    }
}

/// MATRIX-198: the timeline runs under the floating composer.
///
/// The composer's height is the scroll view's bottom content inset. The
/// controller is the app's own `TimelineViewController`, fed synthetic events
/// through the spike's `LiveTimeline` bridge. The tests set the inset the way
/// the representable does (`setBottomContentInset`), then read the geometry:
/// the newest row must rest fully above the composer band, and a row a jump
/// lands on must not be under it.
///
/// The window is borderless and never ordered front.
@MainActor
@Suite("Timeline composer inset", .serialized)
struct TimelineComposerInsetTests {
    /// A one-line composer (field, padding, the 8 pt gap) and a composer with
    /// several lines and a reply bar.
    private static let oneLineInset: CGFloat = 62
    private static let multiLineInset: CGFloat = 168

    private typealias Mounted = ComposerInsetMount

    // MARK: - Inset and bottom pin

    @Test("At a one-line and a multi-line composer, the bottom pin rests the newest row above the composer", arguments: [
        // `oneLineInset` and `multiLineInset`: the arguments run off the
        // main actor, so they are literals here.
        CGFloat(62),
        CGFloat(168)
    ])
    func insetAndBottomPin(inset: CGFloat) async throws {
        let mounted = Mounted()
        defer { mounted.close() }
        try await mounted.settle(0.3)
        try await mounted.setInset(inset)

        #expect(mounted.controller.scrollView.contentInsets.bottom == inset)
        #expect(mounted.controller.scrollView.automaticallyAdjustsContentInsets == false)
        // The clip view carries the inset, so the scroller and AppKit's own
        // scroll clamp see it.
        #expect(mounted.clipView.contentInsets.bottom == inset)
        #expect(mounted.originY == -inset, "origin \(mounted.originY)")
        #expect(mounted.controller.distanceFromNewestEnd == 0)
        #expect(mounted.newestRowBottom >= mounted.composerTop, "the newest row must not be under the composer")
        #expect(mounted.source.isAtBottom)

        // AppKit's own clamp stops a scroll toward the newest end at the inset.
        let constrained = mounted.clipView.constrainBoundsRect(
            NSRect(origin: NSPoint(x: 0, y: -inset - 500), size: mounted.clipView.bounds.size)
        )
        #expect(constrained.origin.y == -inset)

        // The scroller ends at the composer's top.
        let scroller = try #require(mounted.controller.scrollView.verticalScroller)
        let scrollerBottomGap = mounted.controller.scrollView.bounds.height - scroller.frame.maxY
        #expect(scrollerBottomGap >= inset - 1, "scroller bottom gap \(scrollerBottomGap)")
    }

    @Test("A short history rests above the composer")
    func shortHistoryRestsAboveTheComposer() async throws {
        let mounted = Mounted(eventCount: 1)
        defer { mounted.close() }
        try await mounted.settle(0.3)
        try await mounted.setInset(Self.oneLineInset)

        #expect(mounted.originY == -Self.oneLineInset)
        #expect(mounted.newestRowBottom >= mounted.composerTop)
        // The table fills the clip less the inset, so AppKit's clamp agrees.
        let constrained = mounted.clipView.constrainBoundsRect(
            NSRect(origin: NSPoint(x: 0, y: 500), size: mounted.clipView.bounds.size)
        )
        #expect(constrained.origin.y == -Self.oneLineInset)
        #expect(mounted.controller.maximumScrollOriginY == -Self.oneLineInset)
    }

    @Test("A composer height change at the bottom keeps the newest row pinned above the composer")
    func heightChangeKeepsThePin() async throws {
        let mounted = Mounted()
        defer { mounted.close() }
        try await mounted.settle(0.3)
        try await mounted.setInset(Self.oneLineInset)

        let gapBefore = mounted.newestRowBottom - mounted.composerTop
        for inset in [Self.multiLineInset, 90, Self.oneLineInset, Self.multiLineInset, 0, Self.oneLineInset] {
            try await mounted.setInset(inset)
            #expect(mounted.originY == -inset, "at \(inset): origin \(mounted.originY)")
            let gap = mounted.newestRowBottom - mounted.composerTop
            // No jump: the newest row keeps its place on the composer's top.
            #expect(abs(gap - gapBefore) <= 0.5, "at \(inset): gap \(gap) against \(gapBefore)")
            #expect(mounted.source.isAtBottom, "at \(inset)")
        }
    }

    @Test("A composer height change mid-history keeps the content on the composer's top")
    func heightChangeMidHistory() async throws {
        let mounted = Mounted()
        defer { mounted.close() }
        try await mounted.settle(0.3)
        try await mounted.setInset(Self.oneLineInset)
        mounted.measureAllRows()
        try await mounted.scroll(toOriginY: 1200)
        #expect(!mounted.source.isAtBottom)

        let distance = mounted.controller.distanceFromNewestEnd
        try await mounted.setInset(Self.multiLineInset)
        #expect(abs(mounted.controller.distanceFromNewestEnd - distance) <= 0.5)
        #expect(!mounted.source.isAtBottom)
    }

    @Test("The bottom pin counts from the composer: just above the inset is still the bottom")
    func bottomThresholdCountsFromTheInset() async throws {
        let mounted = Mounted()
        defer { mounted.close() }
        try await mounted.settle(0.3)
        try await mounted.setInset(Self.multiLineInset)
        mounted.measureAllRows()

        try await mounted.scroll(toOriginY: -Self.multiLineInset + TimelineViewController.bottomThreshold - 1)
        #expect(mounted.source.isAtBottom)
        try await mounted.scroll(toOriginY: -Self.multiLineInset + TimelineViewController.bottomThreshold + 1)
        #expect(!mounted.source.isAtBottom)
        // Origin 0 is the old bottom: with the inset it is above it.
        try await mounted.scroll(toOriginY: 0)
        #expect(!mounted.source.isAtBottom)
    }

    // MARK: - Covered band

    @Test("The unobscured visible rect leaves out the composer band")
    func unobscuredRectLeavesOutTheBand() async throws {
        let mounted = Mounted()
        defer { mounted.close() }
        try await mounted.settle(0.3)
        try await mounted.setInset(Self.multiLineInset)
        mounted.measureAllRows()
        try await mounted.scroll(toOriginY: 800)

        let visible = mounted.controller.tableView.visibleRect
        let open = mounted.controller.unobscuredVisibleRect
        #expect(open.minY == mounted.composerTop)
        #expect(open.maxY == visible.maxY)
        #expect(abs(visible.height - open.height - Self.multiLineInset) <= 0.5)
    }

    // MARK: - Jump to message

    @Test("A jump lands its target above the composer, for a row under the band and a row below the viewport")
    func jumpTargetIsNotUnderTheComposer() async throws {
        let mounted = Mounted()
        defer { mounted.close() }
        try await mounted.settle(0.3)
        try await mounted.setInset(Self.multiLineInset)
        mounted.measureAllRows()
        let tableView = mounted.controller.tableView
        try await mounted.scroll(toOriginY: 1500)

        // A row whose bottom edge is under the composer band: the old code
        // took it as visible and did not scroll.
        let bandRows = tableView.rows(in: NSRect(
            x: 0, y: mounted.clipView.bounds.minY, width: tableView.bounds.width, height: Self.multiLineInset
        ))
        #expect(bandRows.length > 0, "the band must cover a row")
        let underBand = bandRows.location
        try await jump(mounted, toRow: underBand)
        #expect(tableView.rect(ofRow: underBand).minY >= mounted.composerTop - 0.5, "row \(underBand) under the composer")
        // A row taller than the open part keeps its bottom edge in view.
        let openHeight = mounted.clipView.bounds.height - Self.multiLineInset
        if tableView.rect(ofRow: underBand).height <= openHeight {
            #expect(tableView.rect(ofRow: underBand).maxY <= mounted.clipView.bounds.maxY + 0.5)
        }

        // A newer row well below the viewport.
        try await mounted.scroll(toOriginY: 1500)
        let visible = tableView.rows(in: tableView.visibleRect)
        let belowViewport = max(visible.location - 20, 0)
        #expect(belowViewport < visible.location)
        try await jump(mounted, toRow: belowViewport)
        #expect(tableView.rect(ofRow: belowViewport).minY >= mounted.composerTop - 0.5, "row \(belowViewport) under the composer")

        // The newest row: the scroll-to-bottom path ends at the pin.
        try await mounted.scroll(toOriginY: 1500)
        try await jump(mounted, toRow: 0)
        #expect(mounted.originY == -Self.multiLineInset, "origin \(mounted.originY)")
    }

    /// Moves the viewport to where a focus jump's scroll ends.
    ///
    /// `scrollToFocusedRow` animates to `originYShowingRow(_:)`. The test
    /// writes that origin without the animation: an offscreen window does not
    /// reliably run the animation while other suites share the main actor.
    private func jump(_ mounted: Mounted, toRow row: Int) async throws {
        let target = try #require(
            mounted.controller.tableView.originYShowingRow(row),
            "row \(row) already shows in full"
        )
        try await mounted.scroll(toOriginY: target)
    }

    // MARK: - Live resize (MATRIX-197) with the inset

    @Test("A timeline pinned above the composer stays pinned through a live resize")
    func bottomPinHoldsThroughLiveResize() async throws {
        let mounted = Mounted()
        defer { mounted.close() }
        try await mounted.settle(0.3)
        try await mounted.setInset(Self.multiLineInset)

        let tableView = mounted.controller.tableView
        tableView.viewWillStartLiveResize()
        for size in [NSSize(width: 520, height: 460), NSSize(width: 360, height: 520), NSSize(width: 1000, height: 640)] {
            mounted.controller.view.frame = NSRect(origin: .zero, size: size)
            mounted.controller.view.layoutSubtreeIfNeeded()
            try await mounted.settle()
            #expect(mounted.originY == -Self.multiLineInset, "at \(size): origin \(mounted.originY)")
            #expect(mounted.newestRowBottom >= mounted.composerTop, "at \(size)")
        }
        tableView.viewDidEndLiveResize()
        try await mounted.settle(0.3)
        #expect(mounted.originY == -Self.multiLineInset)
        #expect(mounted.newestRowBottom >= mounted.composerTop)
    }

    @Test("A live resize anchor near the composer holds its row, below origin 0")
    func liveResizeAnchorUsesTheInset() async throws {
        let mounted = Mounted()
        defer { mounted.close() }
        try await mounted.settle(0.3)
        try await mounted.setInset(Self.multiLineInset)
        mounted.measureAllRows()
        // Just past the bottom threshold, so the resize holds a row, and
        // below origin 0, which the old clamp did not allow.
        let startOrigin = -Self.multiLineInset + TimelineViewController.bottomThreshold + 20
        #expect(startOrigin < 0)
        try await mounted.scroll(toOriginY: startOrigin)

        let tableView = mounted.controller.tableView
        let visible = tableView.rows(in: tableView.visibleRect)
        let anchorRow = visible.location + visible.length - 1
        let anchorId = mounted.controller.timelineRows[anchorRow].uniqueId
        func offset() -> CGFloat? {
            guard let row = mounted.controller.timelineRows.firstIndex(where: { $0.uniqueId == anchorId }) else { return nil }
            return mounted.clipView.bounds.maxY - tableView.rect(ofRow: row).maxY
        }
        let offsetBefore = try #require(offset())

        tableView.viewWillStartLiveResize()
        // Narrower and taller: the rows grow, so the anchor needs no clamp.
        mounted.controller.view.frame = NSRect(origin: .zero, size: NSSize(width: 600, height: 520))
        mounted.controller.view.layoutSubtreeIfNeeded()
        try await mounted.settle()
        let during = try #require(offset())
        #expect(abs(during - offsetBefore) <= 1, "during: \(during) against \(offsetBefore), origin \(mounted.originY)")
        tableView.viewDidEndLiveResize()
        try await mounted.settle(0.3)
        let after = try #require(offset())
        #expect(abs(after - offsetBefore) <= 1, "after: \(after) against \(offsetBefore)")
        #expect(mounted.originY >= -Self.multiLineInset)
    }
}
