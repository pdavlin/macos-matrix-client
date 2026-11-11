import AppKit
import Models
import SwiftUI
import Tokens
import UI

// MATRIX-145: one floating hover action bar, owned by the timeline
// controller and drawn above all rows.
//
// Before, each row drew its own bar in a SwiftUI overlay that hung about
// 30 points over the row above. Each row is its own view in the table, so
// the row the table drew later covered the overflow, clicks there went to
// the row above, and the row's hover ended as soon as the pointer left its
// bounds. Now the controller tracks the pointer, decides through
// `Models.TimelineHoverBarState`, and places one hosting view in the clip
// view, above the table. A subview of the clip view lives in the same
// scrolled coordinates as the table, so the bar moves with its row without
// work per scroll frame. The controller's side is in
// `TimelineHoverBarController.swift`.

// MARK: - Views

/// The SwiftUI root of the floating bar's hosting view.
struct TimelineHoverBarRoot: View {
    /// The row the bar shows for. Each row gives the bar a new identity, so
    /// the bar reveals again when it moves to another row, as each row's own
    /// bar did before.
    let rowId: String
    let items: [MessageActionItem]
    let isRevealed: Bool
    /// The timeline's base font size. The bar's emoji and symbols draw at
    /// it, as they did inside the row.
    let fontSize: CGFloat
    let perform: @MainActor (MessageAction) -> Void

    /// The root before the bar first shows.
    static let idle = TimelineHoverBarRoot(
        rowId: "",
        items: [],
        isRevealed: false,
        fontSize: CGFloat(TypographyToken.defaultBaseFontSize),
        perform: { _ in }
    )

    /// The same bar, revealed or not. The identity stays, so a hide fades
    /// out in place.
    func revealed(_ isRevealed: Bool) -> TimelineHoverBarRoot {
        TimelineHoverBarRoot(rowId: rowId, items: items, isRevealed: isRevealed, fontSize: fontSize, perform: perform)
    }

    var body: some View {
        HoverActionBar(items: items, isRevealed: isRevealed, perform: perform)
            .font(.system(size: fontSize))
            .id(rowId)
            .padding(HoverActionBarGeometry.hostMargin)
    }
}

/// The hosting view of the floating bar. It takes clicks only on the bar
/// while the bar shows. Its clear margin (`HoverActionBarGeometry.hostMargin`)
/// and a hidden bar pass every click to the rows under them.
final class TimelineHoverBarHostingView: NSHostingView<TimelineHoverBarRoot> {
    /// Whether the bar shows and takes clicks.
    var acceptsClicks = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsClicks, let superview = unsafe superview else { return nil }
        let local = convert(point, from: superview)
        let margin = HoverActionBarGeometry.hostMargin
        guard bounds.insetBy(dx: margin, dy: margin).contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// The owner of the timeline's hover tracking area. A plain responder, so
/// the tracking area does not route the pointer through the controller's
/// responder chain.
final class TimelineHoverTracker: NSResponder {
    var onMove: (@MainActor (NSPoint) -> Void)?
    var onExit: (@MainActor () -> Void)?

    override func mouseEntered(with event: NSEvent) {
        onMove?(event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        onMove?(event.locationInWindow)
    }

    override func mouseExited(with _: NSEvent) {
        onExit?()
    }
}

// MARK: - Storage and drawing

/// The floating hover bar of one timeline: its hosting view, the pointer
/// tracking, the hover state, and the timers. The decisions that need the
/// table live in the `TimelineViewController` extension below; this object
/// only holds state and draws.
@MainActor
final class TimelineHoverBarOverlay {
    let host = TimelineHoverBarHostingView(rootView: .idle)
    let tracker = TimelineHoverTracker()

    /// What the bar shows for. Row IDs are `TimelineRow.uniqueId`.
    var state = TimelineHoverBarState<String>()

    /// The row whose hover background is on. It follows `state.shownRow`;
    /// the table's row provider reads it for every row it builds.
    var highlightedRowId: String?

    /// The row the bar is placed at, while the bar shows.
    private(set) var placedRowId: String?
    /// The message the bar acts on (`MessageActionTarget.key`), while the
    /// bar shows. The reaction picker reads it to anchor at the bar.
    private(set) var placedTargetKey: String?
    /// The bar's frame in the table's coordinates, while the bar shows.
    private(set) var barFrameInTable: CGRect?
    /// The bar's size without the host margin.
    private(set) var barSize: CGSize = .zero

    /// The table row the pointer was over at the last move. A move inside
    /// the same row does nothing more than this compare.
    var lastPointerRow: Int?
    /// Whether the pointer is inside the timeline.
    var isPointerInside = false
    /// The cell rect of the shown row when it was last placed, so a layout
    /// pass that did not move the row costs nothing.
    var shownCellRect: CGRect?

    /// Bumped on every content change, so a stale observation callback
    /// does nothing.
    var contentGeneration = 0

    private var root = TimelineHoverBarRoot.idle
    private var hostHideGeneration = 0
    /// One timer for the end of a scroll. Each scroll frame moves its fire
    /// date instead of making a new timer, as the sticky day pill does.
    private var scrollSettleTimer: Timer?
    private var sheetObservers: [NSObjectProtocol] = []

    /// Adds the hosting view and the tracking area to the clip view.
    func install(in clipView: NSClipView) {
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = []
        // The bar takes its size from `barSize`, set by the controller; the
        // host must not size itself, or it would fight the frame.
        host.sizingOptions = []
        host.isHidden = true
        host.setAccessibilityElement(false)
        clipView.addSubview(host)

        let area = NSTrackingArea(
            rect: .zero,
            // `activeAlways` as SwiftUI's `onHover` uses, so the bar shows
            // in the same windows and app states as each row's bar did.
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: tracker,
            userInfo: nil
        )
        clipView.addTrackingArea(area)
    }

    /// Shows the bar for `rowId` with `items`. The bar's size comes from
    /// the tokens (`HoverActionBarGeometry.barSize(for:)`), not from a
    /// layout pass.
    func show(
        rowId: String,
        targetKey: String,
        items: [MessageActionItem],
        fontSize: CGFloat,
        perform: @escaping @MainActor (MessageAction) -> Void
    ) {
        hostHideGeneration &+= 1
        placedRowId = rowId
        placedTargetKey = targetKey
        barSize = HoverActionBarGeometry.barSize(for: items)
        root = TimelineHoverBarRoot(rowId: rowId, items: items, isRevealed: true, fontSize: fontSize, perform: perform)
        host.isHidden = false
        host.rootView = root
    }

    /// Puts the bar at `frame`, in the table's coordinates.
    func place(atTableFrame frame: CGRect, table: NSTableView) {
        barFrameInTable = frame
        let margin = HoverActionBarGeometry.hostMargin
        guard let clipView = unsafe host.superview else { return }
        let hostFrame = clipView.convert(frame, from: table).insetBy(dx: -margin, dy: -margin)
        if host.frame != hostFrame {
            host.frame = hostFrame
        }
        host.acceptsClicks = true
    }

    /// Fades the bar out where it is, then hides the hosting view.
    func hide() {
        guard placedRowId != nil || barFrameInTable != nil else { return }
        placedRowId = nil
        placedTargetKey = nil
        barFrameInTable = nil
        host.acceptsClicks = false
        root = root.revealed(false)
        host.rootView = root

        // A hidden view shows no tooltips and tracks no hover. Hide it once
        // the fade is over, unless the bar showed again in the meantime.
        hostHideGeneration &+= 1
        let generation = hostHideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionToken.revealDuration * 2) { [weak self] in
            guard let self, generation == hostHideGeneration else { return }
            host.isHidden = true
        }
    }

    /// Hides the bar at once, for a timeline that goes away.
    func hideNow() {
        hide()
        hostHideGeneration &+= 1
        host.isHidden = true
    }

    /// Moves the end-of-scroll timer to `HoverBarToken.scrollSettleDelay`
    /// from now, and makes it if there is none.
    func scheduleScrollSettle(_ settled: @escaping @MainActor @Sendable () -> Void) {
        let fireDate = Date(timeIntervalSinceNow: HoverBarToken.scrollSettleDelay)
        if let scrollSettleTimer, scrollSettleTimer.isValid {
            scrollSettleTimer.fireDate = fireDate
            return
        }
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { settled() }
        }
        // Common modes, so the timer also runs while a scroll is tracking.
        RunLoop.main.add(timer, forMode: .common)
        scrollSettleTimer = timer
    }

    /// Hides the bar while a sheet is open on `window`.
    func observeSheets(on window: NSWindow, changed: @escaping @MainActor @Sendable (Bool) -> Void) {
        stopObservingSheets()
        let center = NotificationCenter.default
        sheetObservers = [
            center.addObserver(forName: NSWindow.willBeginSheetNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { changed(true) }
            },
            center.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { changed(false) }
            },
        ]
    }

    func stopObservingSheets() {
        sheetObservers.forEach(NotificationCenter.default.removeObserver)
        sheetObservers = []
    }
}
