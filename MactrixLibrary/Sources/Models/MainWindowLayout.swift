import Foundation

/// The widths that keep a window's split view and the window itself bounded
/// (MATRIX-266).
///
/// On macOS 27 a `NavigationSplitView` with an inspector is two split views:
/// the inspector floats over the trailing edge of the content column, and
/// the window's minimum width is the sidebar, the detail's minimum, and the
/// inspector added together. When a column has no maximum width and the
/// three do not fit, that column takes each point the window grows by, so
/// the minimum stays ahead of the window on every layout pass. The window
/// then grows until AppKit stops the loop with an exception (the MATRIX-266
/// crash: a 14,774 pt window). With a maximum, the column stops at it and
/// the window grows one time, to the sum of the three. On macOS 26 the
/// window's minimum has the inspector two times, so the window there is
/// wider, but it also stops when the columns stop at their maximum.
public enum MainWindowLayout {
    /// The widest a sidebar or an inspector column gets, in points. The
    /// search inspector had this maximum before MATRIX-266.
    public static let maximumColumnWidth: Double = 600

    /// The widest a window's content gets: the width of all the screens
    /// together.
    ///
    /// A window that is wider than every screen together only comes from a
    /// layout loop. Content that wants more stays at this width, so the loop
    /// cannot push the window past the screens.
    ///
    /// - Parameter screenFrames: the frames of the screens, in global
    ///   coordinates.
    /// - Returns: the width of the smallest rectangle that holds every
    ///   screen, or nil with no usable screen (no limit).
    public static func maximumContentWidth(screenFrames: [CGRect]) -> Double? {
        let usable = screenFrames.filter { frame in
            !frame.isNull && !frame.isInfinite && frame.width.isFinite && frame.width > 0
        }
        guard let first = usable.first else { return nil }
        let bounds = usable.dropFirst().reduce(first) { $0.union($1) }
        return Double(bounds.width)
    }
}
