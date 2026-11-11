import Foundation

/// Which message row the timeline's floating hover bar shows for
/// (MATRIX-145).
///
/// The Mac timeline draws one hover action bar above all its rows, not one
/// bar inside each row: a bar inside a row hangs over the row above, and the
/// row that the table draws later can cover it. The timeline controller
/// tracks the pointer and feeds this type the events below. This type only
/// decides; the controller draws.
///
/// The rules:
/// - The bar follows the message row under the pointer. A row that takes no
///   bar (a day divider, a state event, the typing or pagination row) and
///   the space outside the rows hide it.
/// - The bar stays on its row while the pointer is over the bar, also where
///   the bar covers a neighbor row.
/// - A scroll hides the bar. The content moves under a still pointer, so the
///   row under the pointer is not known until the scroll stops. The
///   controller then reports the pointer again.
/// - A sheet or the reaction picker hides the bar while it is open.
/// - The bar hides when the pointer leaves the timeline.
///
/// `RowID` is the row identity (`TimelineRow.uniqueId` in the app).
public struct TimelineHoverBarState<RowID: Hashable & Sendable>: Equatable, Sendable {
    /// Why the bar is hidden while the pointer is over a message row.
    public enum Suppression: Hashable, Sendable, CaseIterable {
        /// A sheet is open on the window.
        case sheet
        /// The reaction picker popover is open.
        case reactionPicker
    }

    /// One input from the timeline controller.
    public enum Event: Equatable, Sendable {
        /// The pointer moved over a row. The ID is nil for a row that takes
        /// no bar, or for space with no row.
        case pointerOverRow(RowID?)
        /// The pointer moved over the bar that shows now.
        case pointerOverBar
        /// The pointer left the timeline.
        case pointerExited
        /// The timeline started to scroll.
        case scrollBegan
        /// The timeline stopped scrolling.
        case scrollEnded
        /// A sheet or the picker opened.
        case suppress(Suppression)
        /// A sheet or the picker closed.
        case unsuppress(Suppression)
        /// The row left the timeline.
        case rowRemoved(RowID)
    }

    /// The message row the pointer is over, or the row whose bar the
    /// pointer is over. Nil when neither.
    public private(set) var hoveredRow: RowID?

    /// True from a scroll's first movement until it stops.
    public private(set) var isScrolling = false

    /// The open sheets and pickers that hide the bar.
    public private(set) var suppressions: Set<Suppression> = []

    public init() {}

    /// The row the bar shows for, or nil when the bar is hidden. The row's
    /// hover highlight follows the same value, so the bar and the highlight
    /// always mark one row.
    public var shownRow: RowID? {
        guard !isScrolling, suppressions.isEmpty else { return nil }
        return hoveredRow
    }

    /// Applies one event.
    ///
    /// - Parameter event: The input.
    /// - Returns: Whether `shownRow` changed.
    @discardableResult
    public mutating func apply(_ event: Event) -> Bool {
        let before = shownRow
        switch event {
        case let .pointerOverRow(row):
            hoveredRow = row
        case .pointerOverBar:
            // The bar keeps its row. The pointer can only be over a bar
            // that shows, so there is nothing to change.
            break
        case .pointerExited:
            hoveredRow = nil
        case .scrollBegan:
            isScrolling = true
            // The content moves under the pointer. The row under it is
            // reported again when the scroll stops.
            hoveredRow = nil
        case .scrollEnded:
            isScrolling = false
        case let .suppress(suppression):
            suppressions.insert(suppression)
        case let .unsuppress(suppression):
            suppressions.remove(suppression)
        case let .rowRemoved(row):
            if hoveredRow == row {
                hoveredRow = nil
            }
        }
        return shownRow != before
    }
}
