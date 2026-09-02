import SwiftUI

/// Accent tokens for timeline rows.
///
/// The rows derive their focus/hover chrome from the system accent color; the
/// opacities at which that chrome is applied live here so the accent can be
/// re-tuned without touching row views.
public enum AccentToken {
    /// Opacity of the accent-colored background behind the focused row.
    public static let focusBackgroundOpacity: Double = 0.1

    /// Opacity of the gray background behind a hovered row.
    public static let hoverBackgroundOpacity: Double = 0.1

    /// Row background opacity when the row is neither hovered nor focused.
    public static let inactiveBackgroundOpacity: Double = 0.001

    /// Row background opacity when the row is hovered or focused.
    public static let activeBackgroundOpacity: Double = 1
}
