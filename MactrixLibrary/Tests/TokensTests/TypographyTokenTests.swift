import SwiftUI
import Testing
@testable import Tokens

/// The first migrated token: the historical `@AppStorage("fontSize")` value
/// must keep working under the same storage key so existing user settings
/// carry over (decision D-5).
@Suite("Typography tokens")
struct TypographyTokenTests {
    @Test
    func storageKeyIsPreserved() {
        #expect(TypographyToken.fontSizeStorageKey == "fontSize")
    }

    @Test
    func defaultBoundsMatchHistoricalValues() {
        #expect(TypographyToken.defaultBaseFontSize == 13)
        #expect(TypographyToken.minBaseFontSize == 8)
        #expect(TypographyToken.maxBaseFontSize == 24)
    }

    @Test
    func defaultScaleUsesTheHistoricalBaseSize() {
        #expect(TimelineTypography.default.base == 13)
    }

    @Test
    func baseSizeIsClampedToTokenBounds() {
        #expect(TimelineTypography(base: 3).base == 8)
        #expect(TimelineTypography(base: 100).base == 24)
        #expect(TimelineTypography(base: 13).base == 13)
    }

    @Test
    func footnoteMatchesFootnotesAtTheDefaultSize() {
        // macOS .footnote is 10pt at the default 13pt base.
        #expect(TimelineTypography.default.footnote == 10)
    }

    @Test
    func footnoteScalesWithTheBaseSize() {
        #expect(TimelineTypography(base: 15).footnote == 12)
        // Never smaller than 9pt, even at the minimum base size.
        #expect(TimelineTypography(base: 8).footnote == 9)
        #expect(TimelineTypography(base: 24).footnote == 21)
    }

    @Test
    func scaleAppliesRelativeToTheBaseSize() {
        let typography = TimelineTypography(base: 13)
        #expect(typography.scaled(by: TypographyToken.heading1Scale) == 13 * 1.8)
        #expect(typography.scaled(by: TypographyToken.heading2Scale) == 13 * 1.4)
        #expect(typography.scaled(by: TypographyToken.bodyScale) == 13)
    }

    @Test
    func typographyDefaultIsAvailableThroughTheEnvironment() {
        #expect(EnvironmentValues().timelineTypography == .default)
    }
}