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

    // MARK: Code font (MATRIX-202)

    @Test
    func codeFontPrefersBerkeleyMonoThenMenlo() {
        #expect(TypographyToken.codeFontFamilies == ["Berkeley Mono", "Menlo"])
    }

    @Test
    func codeFontUsesBerkeleyMonoWhenItIsInstalled() {
        #expect(TypographyToken.codeFontFamily(isInstalled: { _ in true }) == "Berkeley Mono")
    }

    @Test
    func codeFontFallsBackToMenloWithoutBerkeleyMono() {
        #expect(TypographyToken.codeFontFamily(isInstalled: { $0 == "Menlo" }) == "Menlo")
    }

    @Test
    func codeFontIsNilWhenNoFamilyIsInstalled() {
        #expect(TypographyToken.codeFontFamily(isInstalled: { _ in false }) == nil)
    }

    @Test
    func installedCheckFindsMenloAndRejectsAnUnknownFamily() {
        #expect(TypographyToken.isFontFamilyInstalled("Menlo"))
        #expect(!TypographyToken.isFontFamilyInstalled("No Such Font Family MATRIX-202"))
        // A PostScript name is not a family name.
        #expect(!TypographyToken.isFontFamilyInstalled("Menlo-Regular"))
    }

    @Test
    func installedCodeFontFamilyIsAnInstalledFamilyOfTheList() {
        let family = TypographyToken.installedCodeFontFamily
        #expect(family == TypographyToken.codeFontFamily())
        #expect(family.map(TypographyToken.codeFontFamilies.contains) == true)
    }
}
