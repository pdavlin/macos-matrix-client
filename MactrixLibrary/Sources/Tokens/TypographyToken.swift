import CoreText
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

    /// Point size of an emoji-only message body (MATRIX-137): 1 to 9 emoji
    /// and nothing else draw at this size instead of the base size. Fixed,
    /// not scaled from the base, so the jumbo look is the same at every
    /// user font size.
    public static let jumboEmojiSize: CGFloat = 40

    /// Caption/footnote size derived from the active base size.
    public static func footnote(relativeTo base: CGFloat) -> CGFloat {
        max(9, base - 3)
    }

    // MARK: Code font (MATRIX-202)

    /// The font families of code text, most preferred first: inline code,
    /// code blocks, and the recovery key. The first installed family wins.
    ///
    /// Berkeley Mono is a commercial font. The app never bundles it, so it
    /// shows only on a device where the user installed it. Menlo ships with
    /// macOS and iOS.
    ///
    /// Code uses the body size, with no scale: at the same point size, the
    /// x-height of Berkeley Mono is 98% of the system font's (6.73 pt
    /// against 6.84 pt at 13 pt), and Menlo's is 104%.
    public static let codeFontFamilies = ["Berkeley Mono", "Menlo"]

    /// The first family of `families` that `isInstalled` accepts, or nil if
    /// it accepts none.
    public static func codeFontFamily(
        in families: [String] = codeFontFamilies,
        isInstalled: (String) -> Bool = isFontFamilyInstalled
    ) -> String? {
        families.first(where: isInstalled)
    }

    /// The code font family of this process. It resolves once: a font that
    /// the user installs while the app runs shows after a relaunch.
    public static let installedCodeFontFamily: String? = codeFontFamily()

    /// True if a font of the family `family` is installed.
    public static func isFontFamilyInstalled(_ family: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
        let mandatory: Set<CFString> = [kCTFontFamilyNameAttribute]
        return CTFontDescriptorCreateMatchingFontDescriptor(descriptor, mandatory as CFSet) != nil
    }

    /// The SwiftUI font of code text at the body text style: the installed
    /// code family, else the system monospaced font.
    public static var codeFont: Font {
        guard let family = installedCodeFontFamily else {
            return .system(.body, design: .monospaced)
        }
        return .custom(family, size: bodyTextStyleSize, relativeTo: .body)
    }

    /// The point size of the body text style at the default text size.
    private static var bodyTextStyleSize: CGFloat {
        #if os(macOS)
            13
        #else
            17
        #endif
    }
}

/// The active typography scale for a view subtree.
///
/// Settings write the base size; row content views read the derived scale
/// through `EnvironmentValues.timelineTypography`.
public struct TimelineTypography: Equatable, Hashable, Sendable {
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
