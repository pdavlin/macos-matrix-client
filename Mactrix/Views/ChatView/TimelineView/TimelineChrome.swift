import AppKit
import Models
import QuartzCore
import SwiftUI
import Tokens
import UI

// MATRIX-136: the jump-to-message flash and the floating sticky day pill.
//
// Both are drawn over or behind the rows, never inside the measured row
// content, so neither changes a row height. The decisions (which row
// flashes, which day the pill shows) live in `Models` and have unit tests;
// this file only draws them.

// MARK: - Jump-to-message flash

/// The accent wash behind a row that a focus jump landed on.
///
/// A layer-hosting view: it owns its layer, so AppKit never resets the
/// opacity the flash animates. It sits below the row's hosting view and
/// takes no clicks.
final class TimelineJumpFlashView: NSView {
    private static let animationKey = "jumpFlash"

    private let washLayer = CALayer()

    /// Start time of the flash this view shows. Binding the same flash again
    /// (a row view provided twice for one row) does not restart it.
    private var flashStartTime: TimeInterval?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Set the layer before `wantsLayer`: that makes the view layer-hosting.
        layer = washLayer
        wantsLayer = true
        // The row view also sets the frame on each size change; this keeps
        // the margins if a resize reaches the row another way.
        autoresizingMask = [.width, .height]
        washLayer.opacity = 0
        washLayer.cornerRadius = BubbleToken.cornerRadius
        // No implicit animations: the frame follows the row at once, and
        // only the flash animation moves the opacity.
        washLayer.actions = [
            "opacity": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "backgroundColor": NSNull(),
        ]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    /// Shows the flash that started at `startTime`, `elapsed` seconds in.
    ///
    /// The model opacity stays 0, so the wash is gone when the animation ends
    /// or is removed.
    func play(startTime: TimeInterval, elapsed: TimeInterval) {
        guard flashStartTime != startTime else { return }
        flashStartTime = startTime

        // The accent can change between flashes, so resolve it now, in the
        // row's appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            washLayer.backgroundColor = NSColor.controlAccentColor.cgColor
        }

        let keyframes = TimelineJumpFlash.keyframes(
            peakOpacity: MotionToken.jumpFlashPeakOpacity,
            peakFraction: TimelineChromeToken.jumpFlashPeakFraction,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = keyframes.values.map { Float($0) }
        animation.keyTimes = keyframes.keyTimes.map { NSNumber(value: $0) }
        animation.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeOut),
            count: max(keyframes.values.count - 1, 0)
        )
        animation.duration = MotionToken.jumpFlashDuration
        // A begin time in the past continues a flash on a recycled row view
        // at the point it reached.
        animation.beginTime = washLayer.convertTime(CACurrentMediaTime(), from: nil) - elapsed
        animation.isRemovedOnCompletion = true
        washLayer.add(animation, forKey: Self.animationKey)
    }

    /// Removes the flash at once.
    func stop() {
        guard flashStartTime != nil else { return }
        flashStartTime = nil
        washLayer.removeAnimation(forKey: Self.animationKey)
    }
}

extension TimelineViewController {
    /// Scrolls to the row a focus request resolved to, and flashes the row
    /// when the scroll lands.
    func scrollToFocusedRow(_ rowIndex: Int) {
        guard timelineRows.indices.contains(rowIndex) else { return }
        // Identity, not index: rows can renumber during the scroll.
        let rowId = timelineRows[rowIndex].uniqueId
        jumpFlash.request(rowId: rowId)
        tableView.animateRowToVisible(rowIndex) { [weak self] in
            self?.jumpFlashLanded(onRowId: rowId)
        }
    }

    /// Starts the flash if this landing belongs to the latest focus request,
    /// and updates every row view on the screen: the target starts, a row
    /// that flashed for an older jump clears.
    private func jumpFlashLanded(onRowId rowId: String) {
        guard jumpFlash.land(rowId: rowId, at: CACurrentMediaTime()) else { return }
        tableView.enumerateAvailableRowViews { rowView, row in
            guard let rowView = rowView as? TimelineMessageRowView else { return }
            applyJumpFlash(to: rowView, atRow: row)
        }
    }

    /// Gives a row view the flash state of the row it shows now. Called
    /// every time a row view is provided, so a recycled view never carries a
    /// flash to the wrong row.
    func applyJumpFlash(to rowView: TimelineMessageRowView, atRow row: Int) {
        guard let current = jumpFlash.current,
              timelineRows.indices.contains(row),
              let elapsed = jumpFlash.elapsed(forRowId: timelineRows[row].uniqueId, at: CACurrentMediaTime())
        else {
            rowView.clearJumpFlash()
            return
        }
        rowView.showJumpFlash(startTime: current.startTime, elapsed: elapsed)
    }
}

// MARK: - Sticky day pill

/// The hosting view of the sticky day pill. It takes no clicks and no
/// scroll events: they go to the timeline under it.
final class StickyDayPillHostingView: NSHostingView<StickyDayPill> {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

/// The floating day pill pinned near the top of the timeline.
///
/// It fades in while the timeline scrolls, and fades out
/// `TimelineChromeToken.stickyDayPillIdleDelay` after the scrolling stops.
/// It hides at once while a real date divider is under it. Opaque, never
/// glass. It lives in the scroll view, above the clip view, not in the table.
@MainActor
final class TimelineStickyDayPillOverlay {
    private let host = StickyDayPillHostingView(rootView: StickyDayPill(date: .distantPast))
    /// The day the pill shows. The SwiftUI root view changes only when the
    /// day changes, not on every scroll frame.
    private var shownDay: Date?
    private var isShown = false
    private var lastOriginY: CGFloat = 0
    /// One timer for the idle fade-out. Each scroll frame moves its fire date
    /// instead of making a new timer.
    private var idleTimer: Timer?

    /// Adds the pill to the scroll view, hidden.
    func install(in scrollView: NSScrollView) {
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.alphaValue = 0
        host.setAccessibilityElement(false)
        scrollView.addSubview(host)
        // The timeline runs under the toolbar, so the pill hangs from the
        // safe area, not from the scroll view edge. The host adds a shadow
        // margin around the pill, so subtract it.
        NSLayoutConstraint.activate([
            host.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            host.topAnchor.constraint(
                equalTo: scrollView.safeAreaLayoutGuide.topAnchor,
                constant: TimelineChromeToken.stickyDayPillTopInset - TimelineChromeToken.stickyDayPillShadowMargin
            ),
        ])
        lastOriginY = scrollView.contentView.bounds.origin.y
    }

    /// Records the scroll origin and tells whether it moved. A bounds change
    /// that does not move the origin (a width change) is not scrolling.
    func originDidMove(to originY: CGFloat) -> Bool {
        defer { lastOriginY = originY }
        return originY != lastOriginY
    }

    /// Shows `day` while the timeline scrolls, or hides the pill at once for
    /// nil (a date divider is under the pill, or no row has a date).
    func scrolled(showing day: Date?) {
        guard let day else {
            setShown(false, duration: 0)
            return
        }
        if day != shownDay {
            shownDay = day
            host.rootView = StickyDayPill(date: day)
        }
        setShown(true, duration: MotionToken.stateDuration)
        scheduleIdleFadeOut()
    }

    private func scheduleIdleFadeOut() {
        let fireDate = Date(timeIntervalSinceNow: TimelineChromeToken.stickyDayPillIdleDelay)
        if let idleTimer, idleTimer.isValid {
            idleTimer.fireDate = fireDate
            return
        }
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setShown(false, duration: TimelineChromeToken.stickyDayPillFadeOutDuration)
            }
        }
        // Common modes, so the timer also runs while a scroll is tracking.
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    /// Fades the pill in or out. Reduce Motion makes the change instant.
    private func setShown(_ shown: Bool, duration: TimeInterval) {
        guard shown != isShown else { return }
        isShown = shown
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            host.animator().alphaValue = shown ? 1 : 0
        }
    }
}

extension TimelineViewController {
    /// Adds the sticky day pill over the timeline. Call once, after the
    /// scroll view is the controller's view.
    func installStickyDayPill() {
        stickyDayPill.install(in: scrollView)
    }

    /// Updates the sticky day pill for a bounds change.
    ///
    /// The only per-frame work: compare the origin, read the rows under the
    /// pill (a binary search in the table), and look up their day.
    func updateStickyDayPill() {
        guard stickyDayPill.originDidMove(to: scrollView.contentView.bounds.origin.y) else { return }

        // The table is not flipped: the top of the visible rect is maxY. The
        // timeline runs under the toolbar, so the pill band starts below the
        // safe area top.
        let visible = tableView.visibleRect
        let band = TimelineChromeToken.stickyDayPillEdgeBand
        let bandTop = visible.maxY - scrollView.safeAreaInsets.top
        let bandRect = NSRect(x: visible.minX, y: bandTop - band, width: max(visible.width, 1), height: band)
        let rowsUnderPill = Range(tableView.rows(in: bandRect)) ?? 0 ..< 0

        let day = TimelineStickyDay.day(rows: timelineRows, rowsAtTopEdge: rowsUnderPill, calendar: groupingCalendar)
        stickyDayPill.scrolled(showing: day)
    }
}
