import SwiftUI

/// The typography scale the timeline consumes, driven by the user-tunable base size.
///
/// The base size is the first migrated token: it backs the historical
/// `@AppStorage("fontSize")` value under the same storage key so existing user
/// settings carry over unchanged (decision D-5).
public enum TypographyToken {
    /// Storage key backing the user-tunable base font size.
    public static let fontSizeStorageKey = "fontSize"

    /// Base font size used when the user has never set one.
    public static let defaultBaseFontSize: Int = 13

    /// Smallest selectable base font size.
    public static let minBaseFontSize: Int = 8

    /// Largest selectable base font size.
    public static let maxBaseFontSize: Int = 24

    // MARK: Scale (relative to the active base size)

    /// Body-copy multiplier (identity).
    public static let bodyScale: CGFloat = 1.0

    /// H1 multiplier, used for formatted-message headings.
    public static let heading1Scale: CGFloat = 1.8

    /// H2 multiplier, used for formatted-message headings.
    public static let heading2Scale: CGFloat = 1.4

    /// H3 multiplier, used for formatted-message headings.
    public static let heading3Scale: CGFloat = 1.2

    /// H4 multiplier, used for formatted-message headings.
    public static let heading4Scale: CGFloat = 1.1

    /// Paragraph spacing multiplier applied between paragraphs.
    public static let paragraphSpacingScale: CGFloat = 0.4

    /// Paragraph spacing multiplier applied before headings.
    public static let paragraphSpacingBeforeScale: CGFloat = 0.8

    /// Caption/footnote size derived from the active base size.
    public static func footnote(relativeTo base: CGFloat) -> CGFloat {
        max(9, base - 3)
    }
}

/// The active typography scale for a view subtree.
///
/// Settings write the base size; row content views read the derived scale
/// through `EnvironmentValues.timelineTypography`.
public struct TimelineTypography: Equatable, Sendable {
    /// The user-tunable base size in points, clamped to the token bounds.
    public let base: CGFloat

    public init(base: CGFloat) {
        let minBase = CGFloat(TypographyToken.minBaseFontSize)
        let maxBase = CGFloat(TypographyToken.maxBaseFontSize)
        self.base = min(max(minBase, base), maxBase)
    }

    /// The scale used when nothing has set a base size yet.
    public static let `default` = TimelineTypography(base: CGFloat(TypographyToken.defaultBaseFontSize))

    /// Footnote-size text (timestamps, secondary captions).
    public var footnote: CGFloat {
        TypographyToken.footnote(relativeTo: base)
    }

    /// Applies a token scale factor to the active base size.
    public func scaled(by factor: CGFloat) -> CGFloat {
        base * factor
    }
}

/// Provides `EnvironmentValues.timelineTypography` so settings can write the
/// scale once and every row in the subtree reads the same values.
public extension EnvironmentValues {
    /// The typography scale active for the timeline subtree.
    @Entry var timelineTypography = TimelineTypography.default
}
