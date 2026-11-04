import AppKit
import SwiftUI

/// Colors, icons, and metrics for chat labels and the sidebar label rail
/// (MATRIX-77).
///
/// The rail follows a static teardown of Beeper Desktop 4.3.229's space bar.
/// The palette is defined in code, not in the app's asset catalog: named
/// asset colors do not resolve inside this package or its snapshot tests.
public enum LabelToken {
    // MARK: Palette

    /// One label color, with a light and a dark variant.
    public struct PaletteColor: Sendable {
        public let name: String
        let light: UInt32
        let dark: UInt32

        /// The color for the current appearance.
        public var color: Color {
            let light = light
            let dark = dark
            return Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(rgb: isDark ? dark : light)
            })
        }
    }

    /// The label colors, by `ChatLabel.colorIndex`. Append only: the index is
    /// stored in account data, so reordering recolors every saved label.
    public static let palette: [PaletteColor] = [
        PaletteColor(name: "Red", light: 0xE5484D, dark: 0xF2555A),
        PaletteColor(name: "Orange", light: 0xEF6C1A, dark: 0xF4843A),
        PaletteColor(name: "Amber", light: 0xD99A0B, dark: 0xE8AE2C),
        PaletteColor(name: "Green", light: 0x30A46C, dark: 0x3DB57B),
        PaletteColor(name: "Teal", light: 0x12A594, dark: 0x1DB5A3),
        PaletteColor(name: "Cyan", light: 0x0797B9, dark: 0x1AA9CA),
        PaletteColor(name: "Blue", light: 0x0D74CE, dark: 0x3B8EEA),
        PaletteColor(name: "Indigo", light: 0x3E63DD, dark: 0x5B7BE6),
        PaletteColor(name: "Purple", light: 0x8E4EC6, dark: 0xA067D3),
        PaletteColor(name: "Pink", light: 0xD6409F, dark: 0xE05AAF),
        PaletteColor(name: "Brown", light: 0x9E6C46, dark: 0xB2835E),
        PaletteColor(name: "Slate", light: 0x60646C, dark: 0x7C808A),
    ]

    /// The fill for `colorIndex`. Nil, or an index this build does not know,
    /// is the neutral fill.
    public static func fill(for colorIndex: Int?) -> Color {
        guard let colorIndex, palette.indices.contains(colorIndex) else { return neutralFill }
        return palette[colorIndex].color
    }

    /// The glyph color on `fill(for:)`.
    public static func glyph(for colorIndex: Int?) -> Color {
        guard let colorIndex, palette.indices.contains(colorIndex) else { return .primary }
        return .white
    }

    /// The fill of a label with no color.
    public static let neutralFill = Color.primary.opacity(0.12)

    // MARK: Icons

    /// The curated SF Symbols a label can use. Every name exists on macOS 26
    /// (pinned by `LabelTokenTests`). Stored by name, so removing one leaves
    /// saved labels with a monogram.
    public static let icons: [String] = [
        "briefcase",
        "house",
        "person.2",
        "star",
        "heart",
        "cart",
        "airplane",
        "gamecontroller",
        "book",
        "music.note",
        "graduationcap",
        "hammer",
        "leaf",
        "pawprint",
        "flag",
        "bell",
        "tag",
        "folder",
        "bubble.left.and.bubble.right",
        "building.2",
        "sportscourt",
        "fork.knife",
        "car",
        "globe",
    ]

    // MARK: Rail

    /// Width of the rail column, padding included.
    public static let railWidth: CGFloat = 68

    /// Side of an item's button: its hit area and selected background.
    public static let railItemSize: CGFloat = 48

    /// Corner radius of an item's selected background (Beeper: 14 px).
    public static let railItemCornerRadius: CGFloat = 14

    /// Side of the colored square that carries the icon.
    public static let railIconSize: CGFloat = 32

    /// Corner radius of the colored square.
    public static let railIconCornerRadius: CGFloat = 9

    /// Point size of the SF Symbol in the colored square.
    public static let railGlyphSize: CGFloat = 16

    /// Point size of the monogram, set bold.
    public static let railMonogramSize: CGFloat = 15

    /// Vertical spacing between items.
    public static let railItemSpacing: CGFloat = 4

    /// Padding above the first item and below the "+" button.
    public static let railVerticalPadding: CGFloat = 10

    /// Opacity of the primary color behind the selected item.
    public static let railSelectedOpacity: Double = 0.12

    /// Opacity of a muted label's colored square.
    public static let railMutedOpacity: Double = 0.45

    /// Diameter of the round mark that carries a muted label's bell.
    public static let railMutedMarkSize: CGFloat = 15

    /// Point size of the muted bell.
    public static let railMutedGlyphSize: CGFloat = 8

    // MARK: Badge

    /// Diameter of the plain unread dot (Beeper's AccountBadge: 8 px).
    public static let badgeDotSize: CGFloat = 8

    /// Unread-count size, set bold (Beeper: 10 px).
    public static let badgeCountFontSize: CGFloat = 10

    /// Minimum width of the count capsule, so one digit reads as a circle.
    public static let badgeCountMinWidth: CGFloat = 16

    /// Height of the count capsule.
    public static let badgeCountHeight: CGFloat = 16

    /// Horizontal padding inside the count capsule.
    public static let badgeCountHorizontalPadding: CGFloat = 4

    /// How far the badge sits past the colored square's top-right corner.
    public static let badgeOffset: CGFloat = 5

    // MARK: Icon and color picker

    /// Diameter of a color swatch.
    public static let pickerSwatchSize: CGFloat = 24

    /// Side of an icon cell.
    public static let pickerIconCellSize: CGFloat = 28

    /// Point size of the SF Symbol in an icon cell.
    public static let pickerIconGlyphSize: CGFloat = 15

    /// Width of the accent ring or border that marks the selection.
    public static let pickerSelectionWidth: CGFloat = 2

    /// Corner radius of an icon cell.
    public static let pickerIconCellCornerRadius: CGFloat = 6

    /// Spacing between swatches and between icon cells.
    public static let pickerSpacing: CGFloat = 6

    /// Icon cells per row.
    public static let pickerIconColumns: Int = 8

    /// Padding inside the picker popover.
    public static let pickerPadding: CGFloat = 12

    // MARK: Edit sheet

    /// Width of the Create/Edit Label sheet.
    public static let sheetWidth: CGFloat = 440

    /// Height of the chat checklist in the sheet.
    public static let sheetChatListHeight: CGFloat = 280

    /// Avatar diameter in the chat checklist.
    public static let sheetAvatarSize: CGFloat = 24
}

extension NSColor {
    /// An opaque sRGB color from `0xRRGGBB`.
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
