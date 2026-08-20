import SwiftUI

/// The layout spec both candidates must honour.
///
/// S-13 gets it for free through `SpikeRowView`. S-14 draws its own `NSView` and must match
/// these numbers, otherwise the two candidates lay out different amounts of content and the
/// frame times are not comparable.
public enum SpikeRowMetrics {
    public static let horizontalPadding: CGFloat = 16
    public static let verticalPadding: CGFloat = 4
    public static let runLeadingInset: CGFloat = 44
    public static let avatarSize: CGFloat = 32
    public static let avatarTextGap: CGFloat = 12
    public static let headerBodyGap: CGFloat = 2
    public static let reactionTopGap: CGFloat = 4
    public static let daySeparatorHeight: CGFloat = 34
    public static let bodyFontSize: CGFloat = 13
    public static let headerFontSize: CGFloat = 13
    public static let metaFontSize: CGFloat = 11
    public static let maximumImageWidth: CGFloat = 420
    public static let minimumImageHeight: CGFloat = 80
    public static let maximumImageHeight: CGFloat = 520

    public static let bodyFont = Font.system(size: bodyFontSize)
    public static let headerFont = Font.system(size: headerFontSize, weight: .semibold)
    public static let metaFont = Font.system(size: metaFontSize)

    /// Rendered size for an image placeholder inside a given content width.
    public static func imageSize(
        for placeholder: ImagePlaceholder,
        availableWidth: CGFloat
    ) -> CGSize {
        let width = min(min(CGFloat(placeholder.intrinsicWidth), maximumImageWidth), availableWidth)
        let rawHeight = width / max(0.05, CGFloat(placeholder.aspectRatio))
        let height = min(max(rawHeight, minimumImageHeight), maximumImageHeight)
        return CGSize(width: max(width, 1), height: height)
    }

    public static func color(forHue hue: Double) -> Color {
        Color(hue: hue, saturation: 0.55, brightness: 0.72)
    }

    /// Time-of-day label. UTC, matching `Calendar.spikeUTC`, so it agrees with the day
    /// separators.
    public static func timeLabel(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    public static func dayLabel(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .spikeUTC
        formatter.timeZone = .gmt
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .spikeUTC
        formatter.timeZone = .gmt
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter
    }()
}
