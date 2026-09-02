import SwiftUI

/// Message-bubble styling tokens: radii, borders, shadows, and the muted
/// background opacities that shape message chrome.
public enum BubbleToken {
    /// Corner radius for message chrome (focus/hover backgrounds, pills, replies).
    public static let cornerRadius: CGFloat = 4

    /// Shadow radius under the hover action bar.
    public static let hoverShadowRadius: CGFloat = 4

    /// Shadow opacity under the hover action bar.
    public static let hoverShadowOpacity: Double = 0.1

    /// Border width of the hover action bar.
    public static let hoverBorderWidth: CGFloat = 1

    /// Corner radius for media thumbnails embedded in messages.
    public static let mediaCornerRadius: CGFloat = 6

    /// The tallest an inline media row (image or video) will render, in points.
    public static let mediaMaxHeight: CGFloat = 300

    /// Width of the left accent bar in embedded replies.
    public static let replyBarWidth: CGFloat = 3

    /// Opacity of the left accent bar in embedded replies.
    public static let replyBarOpacity: Double = 0.5

    /// Background opacity of an embedded reply.
    public static let replyBackgroundOpacity: Double = 0.05

    /// Leading inset of the embedded-reply background behind the accent bar.
    public static let replyBackgroundInset: CGFloat = 2

    /// Background opacity of the thread summary button.
    public static let threadSummaryBackgroundOpacity: Double = 0.05
}
