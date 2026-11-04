import AppKit
import Testing
@testable import Tokens

/// MATRIX-77: the label palette and icon set are usable, and the rail
/// metrics match the Beeper teardown.
@Suite("Label tokens")
struct LabelTokenTests {
    @Test
    func everyIconIsAnSFSymbol() {
        for name in LabelToken.icons {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "missing symbol \(name)")
        }
    }

    @Test
    func iconsAreUnique() {
        #expect(Set(LabelToken.icons).count == LabelToken.icons.count)
    }

    @Test
    func paletteHasTwelveNamedColors() {
        #expect(LabelToken.palette.count == 12)
        #expect(Set(LabelToken.palette.map(\.name)).count == 12)
    }

    @Test
    func paletteVariesByAppearance() throws {
        for entry in LabelToken.palette {
            let color = NSColor(entry.color)
            var light: NSColor?
            var dark: NSColor?
            try #require(NSAppearance(named: .aqua)).performAsCurrentDrawingAppearance {
                light = color.usingColorSpace(.sRGB)
            }
            try #require(NSAppearance(named: .darkAqua)).performAsCurrentDrawingAppearance {
                dark = color.usingColorSpace(.sRGB)
            }
            #expect(light != nil)
            #expect(light != dark, "\(entry.name) has the same light and dark value")
        }
    }

    @Test
    func unknownColorIndexIsNeutral() {
        #expect(LabelToken.fill(for: nil) == LabelToken.neutralFill)
        #expect(LabelToken.fill(for: -1) == LabelToken.neutralFill)
        #expect(LabelToken.fill(for: LabelToken.palette.count) == LabelToken.neutralFill)
    }

    @Test
    func railMetricsArePinned() {
        #expect(LabelToken.railWidth == 68)
        #expect(LabelToken.railItemSize == 48)
        #expect(LabelToken.railItemCornerRadius == 14)
        #expect(LabelToken.railIconSize == 32)
        #expect(LabelToken.badgeDotSize == 8)
        #expect(LabelToken.badgeCountFontSize == 10)
        #expect(LabelToken.pickerSwatchSize == 24)
        #expect(LabelToken.pickerIconCellSize == 28)
        #expect(LabelToken.pickerSelectionWidth == 2)
    }
}
