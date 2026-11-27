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
@MainActor
struct MainWindowColumnGrowthTests {
    private static let sidebarMinimum = 240 + LabelToken.railWidth
    private static let sidebarIdeal = 320 + LabelToken.railWidth
    private static let detailMinimum: CGFloat = 250
    private static let inspectorIdeal: CGFloat = 400
    private static let columnMaximum = CGFloat(MainWindowLayout.maximumColumnWidth)

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

    /// Hosts `view` in a window that is not on screen. The hosting view
    /// follows the content's minimum size, as a `WindowGroup` window does
    /// with the default `contentMinSize` resizability.
    private func host(_ view: some View, width: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        host.sizingOptions = [.minSize]
        window.contentView = host
        settle(window)
        return window
    }

    private func settle(_ window: NSWindow) {
        for _ in 0 ..< 3 {
            RunLoop.main.run(until: Date() + 0.01)
            window.layoutIfNeeded()
        }
    }

    private func splitViews(in view: NSView) -> [NSSplitView] {
        let own = (view as? NSSplitView).map { [$0] } ?? []
        return own + view.subviews.flatMap { splitViews(in: $0) }
    }

    /// The split view whose controller has an item of `behavior`.
    private func splitView(with behavior: NSSplitViewItem.Behavior, in window: NSWindow) throws -> NSSplitView {
        let content = try #require(window.contentView)
        return try #require(splitViews(in: content).first { split in
            (split.delegate as? NSSplitViewController)?.splitViewItems.contains { $0.behavior == behavior } ?? false
        })
    }

    /// Moves the first divider of `split` to each position, as a drag does.
    private func drag(_ split: NSSplitView, through positions: StrideThrough<CGFloat>, in window: NSWindow) {
        for position in positions {
            split.setPosition(position, ofDividerAt: 0)
            settle(window)
        }
    }

    @Test func anInspectorDraggedWideStopsAtItsMaximum() throws {
        let window = host(Columns(sidebarMaximum: Self.columnMaximum, inspectorMaximum: Self.columnMaximum), width: 1100)
        defer { window.close() }
        let split = try splitView(with: .inspector, in: window)

        drag(split, through: stride(from: 700, through: 0, by: -100), in: window)

        let inspector = try #require(split.arrangedSubviews.last)
        #expect(inspector.frame.width <= Self.columnMaximum + 0.5)
        // The window grows one time, to the three columns together.
        let columns = Self.sidebarIdeal + Self.detailMinimum + Self.columnMaximum
        #expect(window.frame.width <= columns + 1)
        let settled = window.frame.width
        settle(window)
        #expect(window.frame.width == settled)
    }

    @Test func aSidebarDraggedWideStopsAtItsMaximum() throws {
        let window = host(Columns(sidebarMaximum: Self.columnMaximum, inspectorMaximum: Self.columnMaximum), width: 1400)
        defer { window.close() }
        let split = try splitView(with: .sidebar, in: window)

        drag(split, through: stride(from: Self.sidebarIdeal, through: 2400, by: 100), in: window)

        let sidebar = try #require(split.arrangedSubviews.first)
        #expect(sidebar.frame.width <= Self.columnMaximum + 0.5)
        // The widest sidebar, the detail, and the inspector fit in 1,400 pt.
        #expect(window.frame.width == 1400)
    }

    @Test func theScreenWidthLimitHoldsAWindowWhoseColumnsHaveNoMaximum() throws {
        let screens = [CGRect(x: 0, y: 0, width: 2000, height: 1200)]
        let view = Columns(sidebarMaximum: nil, inspectorMaximum: nil)
            .modifier(ScreenWidthLimit(screenFrames: { screens }))
        let window = host(view, width: 1100)
        defer { window.close() }
        let split = try splitView(with: .inspector, in: window)

        drag(split, through: stride(from: 700, through: 0, by: -100), in: window)

        #expect(window.frame.width <= 2000)
    }
}
