import AppKit
import Models
import SwiftUI
import Testing
import Tokens
@testable import UI

/// MATRIX-266: the main window's columns, hosted as the app hosts them (a
/// `NavigationSplitView` with an inspector, in a window that follows the
/// content's minimum size), and dragged as far as their dividers go.
///
/// On macOS 27 the inspector floats over the content column. When the
/// inspector divider moves in past the room that the sidebar and the
/// detail need, a column with no maximum takes each point the window grows
/// by: with `max: nil` this window went from 1,100 pt to more than
/// 100,000 pt in a few passes. A sidebar with no maximum moves in under the
/// inspector, and the window grows with the drag.
///
/// The tests do not run the main run loop. A run of the run loop inside a
/// test lets Swift Testing start other main-actor tests in it, so the
/// windows of several tests were alive and changing at the same time (the
/// macOS 26 CI runs that stopped with signal 11). `layoutIfNeeded()` does
/// the layout passes that make the window grow, without the run loop. Each
/// window is torn down on the main actor, in an autorelease pool, before
/// its test returns.
@MainActor
@Suite(.serialized)
struct MainWindowColumnGrowthTests {
    private static let sidebarMinimum = 240 + LabelToken.railWidth
    private static let sidebarIdeal = 320 + LabelToken.railWidth
    private static let detailMinimum: CGFloat = 250
    private static let inspectorIdeal: CGFloat = 400
    private static let columnMaximum = CGFloat(MainWindowLayout.maximumColumnWidth)
    /// A test window this wide comes only from a layout loop. A drag stops
    /// when the window gets wider, so a loop fails the test with a report
    /// and does not grow the window until the process stops.
    private static let runawayWidth: CGFloat = 4000

    /// The columns of `MainView`: the sidebar, a chat in the detail, and the
    /// thread panel in the inspector, with the app's widths.
    private struct Columns: View {
        let sidebarMaximum: CGFloat?
        let inspectorMaximum: CGFloat?

        var body: some View {
            NavigationSplitView {
                List(0 ..< 20, id: \.self) { Text("Chat \($0)") }
                    .navigationSplitViewColumnWidth(
                        min: MainWindowColumnGrowthTests.sidebarMinimum,
                        ideal: MainWindowColumnGrowthTests.sidebarIdeal,
                        max: sidebarMaximum
                    )
            } detail: {
                Color.clear
                    .frame(minWidth: MainWindowColumnGrowthTests.detailMinimum, minHeight: 200)
            }
            .inspector(isPresented: .constant(true)) {
                VStack(spacing: 0) {
                    ThreadTimelineHeader(roomName: "#general", replyCount: 4, dismiss: {})
                    Color.clear
                        .frame(minWidth: MainWindowColumnGrowthTests.detailMinimum, minHeight: 200)
                }
                .inspectorColumnWidth(min: 200, ideal: MainWindowColumnGrowthTests.inspectorIdeal, max: inspectorMaximum)
            }
        }
    }

    /// A split view item's view: its split view and its index there.
    @MainActor
    private struct Column {
        let split: NSSplitView
        let index: Int

        var view: NSView {
            split.arrangedSubviews[index]
        }

        /// The divider that a drag of this column's edge moves: the trailing
        /// divider of the first column, else the leading divider. The sidebar
        /// and the inspector can be in one split view, so the first divider
        /// is not always the inspector's.
        var dividerIndex: Int {
            index == 0 ? 0 : index - 1
        }
    }

    private struct ColumnNotFound: Error {}

    /// The window's widths: before a drag, then after each step of it.
    private struct Growth {
        var widths: [CGFloat]

        /// The number of steps after which the window was wider.
        var count: Int {
            zip(widths, widths.dropFirst()).filter { $1 > $0 + 0.5 }.count
        }
    }

    /// Hosts `view` in a window that is not on screen. The hosting view
    /// follows the content's minimum size, as a `WindowGroup` window does
    /// with the default `contentMinSize` resizability. The window is
    /// deferred: it gets no window device and no backing store, so a wide
    /// window takes no memory for its pixels.
    private func host(_ view: some View, width: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        host.sizingOptions = [.minSize]
        window.contentView = host
        settle(window)
        return window
    }

    /// Hosts `view`, gives the window to `body`, then removes the hosting
    /// view and closes the window in an autorelease pool, so no AppKit
    /// object outlives the test.
    private func withWindow(_ view: some View, width: CGFloat, _ body: (NSWindow) throws -> Void) throws {
        try autoreleasepool {
            let window = host(view, width: width)
            defer {
                window.contentView = nil
                window.close()
            }
            try body(window)
        }
    }

    private func settle(_ window: NSWindow) {
        for _ in 0 ..< 3 {
            window.layoutIfNeeded()
        }
    }

    private func splitViews(in view: NSView) -> [NSSplitView] {
        let own = (view as? NSSplitView).map { [$0] } ?? []
        return own + view.subviews.flatMap { splitViews(in: $0) }
    }

    /// The view of the split view item of `behavior`.
    private func column(_ behavior: NSSplitViewItem.Behavior, in window: NSWindow) throws -> Column {
        let content = try #require(window.contentView)
        for split in splitViews(in: content) {
            guard let items = (split.delegate as? NSSplitViewController)?.splitViewItems,
                  let index = items.firstIndex(where: { $0.behavior == behavior }),
                  index < split.arrangedSubviews.count
            else { continue }
            return Column(split: split, index: index)
        }
        Issue.record("No split view item with behavior \(behavior.rawValue).\n\(report(window))")
        throw ColumnNotFound()
    }

    /// The window's split views, their items, and their widths.
    private func report(_ window: NSWindow) -> String {
        var lines = ["window \(window.frame.width) pt, content minimum \(window.contentMinSize.width) pt"]
        for split in window.contentView.map(splitViews(in:)) ?? [] {
            let items = (split.delegate as? NSSplitViewController)?.splitViewItems ?? []
            let described = items.map { item in
                "behavior \(item.behavior.rawValue) min \(item.minimumThickness) max \(item.maximumThickness)"
                    + (item.isCollapsed ? " collapsed" : "")
            }
            lines.append(
                "split view \(split.frame.width) pt, divider \(split.dividerThickness) pt, "
                    + "views \(split.arrangedSubviews.map(\.frame.width)), items \(described)"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Moves the divider of `column` to each position, as a drag does.
    ///
    /// Stops when the window or a split view gets wider than
    /// `runawayWidth`: each further step makes a layout loop go on. A window
    /// that wide is an issue. A split view that wide is an issue only with
    /// `contentCanRunAway` false: behind `ScreenWidthLimit`, columns with no
    /// maximum still loop inside the window, and only the window is held.
    private func drag(
        _ column: Column,
        through positions: StrideThrough<CGFloat>,
        in window: NSWindow,
        contentCanRunAway: Bool = false
    ) -> Growth {
        var growth = Growth(widths: [window.frame.width])
        for position in positions {
            column.split.setPosition(position, ofDividerAt: column.dividerIndex)
            settle(window)
            growth.widths.append(window.frame.width)
            if window.frame.width > Self.runawayWidth {
                Issue.record("The window grew past \(Self.runawayWidth) pt: \(growth.widths)\n\(report(window))")
                break
            }
            let content = window.contentView.map(splitViews(in:)) ?? []
            if content.contains(where: { $0.frame.width > Self.runawayWidth }) {
                if !contentCanRunAway {
                    Issue.record("A split view grew past \(Self.runawayWidth) pt: \(growth.widths)\n\(report(window))")
                }
                break
            }
        }
        // CI runs another macOS version than this Mac. The log shows the
        // layout there, also when the test passes.
        let line = "MainWindowColumnGrowthTests: widths \(growth.widths)\n\(report(window))\n"
        FileHandle.standardError.write(Data(line.utf8))
        return growth
    }

    @Test func anInspectorDraggedWideStopsAtItsMaximum() throws {
        let columns = Columns(sidebarMaximum: Self.columnMaximum, inspectorMaximum: Self.columnMaximum)
        try withWindow(columns, width: 1100) { window in
            let inspector = try column(.inspector, in: window)

            let growth = drag(inspector, through: stride(from: 700, through: 0, by: -100), in: window)

            #expect(inspector.view.frame.width <= Self.columnMaximum + 0.5, Comment(rawValue: report(window)))
            // The window grows one time, to the three columns together, and
            // stops.
            #expect(growth.count <= 1, Comment(rawValue: "\(growth.widths)\n\(report(window))"))
            let settled = window.frame.width
            settle(window)
            #expect(window.frame.width == settled)
        }
    }

    @Test func aSidebarDraggedWideStopsAtItsMaximum() throws {
        let columns = Columns(sidebarMaximum: Self.columnMaximum, inspectorMaximum: Self.columnMaximum)
        try withWindow(columns, width: 1400) { window in
            let sidebar = try column(.sidebar, in: window)

            let growth = drag(sidebar, through: stride(from: Self.sidebarIdeal, through: 2400, by: 100), in: window)

            #expect(sidebar.view.frame.width <= Self.columnMaximum + 0.5, Comment(rawValue: report(window)))
            // The widest sidebar, the detail, and the inspector fit in
            // 1,400 pt.
            #expect(growth.count == 0, Comment(rawValue: "\(growth.widths)\n\(report(window))"))
        }
    }

    @Test func theScreenWidthLimitHoldsAWindowWhoseColumnsHaveNoMaximum() throws {
        let screens = [CGRect(x: 0, y: 0, width: 2000, height: 1200)]
        let view = Columns(sidebarMaximum: nil, inspectorMaximum: nil)
            .modifier(ScreenWidthLimit(screenFrames: { screens }))
        try withWindow(view, width: 1100) { window in
            let inspector = try column(.inspector, in: window)

            let growth = drag(
                inspector,
                through: stride(from: 700, through: 0, by: -100),
                in: window,
                contentCanRunAway: true
            )

            #expect(window.frame.width <= 2000, Comment(rawValue: "\(growth.widths)\n\(report(window))"))
        }
    }
}
