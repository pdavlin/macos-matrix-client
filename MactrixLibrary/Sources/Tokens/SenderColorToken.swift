import SwiftUI

/// The sender-name palette (MATRIX-68).
///
/// Eight hues, each with a light-appearance and a dark-appearance value, in
/// Beeper's slot order so a sender keeps the color a Beeper user knows them
/// by. The slot comes from `Models.SenderColorHash`; own messages take no slot
/// and keep the default text color.
public enum SenderColorToken {
    /// One color as 0-255 sRGB components.
    public struct RGB: Equatable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// One palette slot, with a value for each appearance.
    public struct Swatch: Equatable, Sendable {
        public let name: String
        public let light: RGB
        public let dark: RGB
    }

    /// The palette, in slot order.
    public static let swatches: [Swatch] = [
        Swatch(name: "grass", light: RGB(41, 124, 59), dark: RGB(99, 193, 116)),
        Swatch(name: "amber", light: RGB(173, 87, 0), dark: RGB(241, 161, 13)),
        Swatch(name: "crimson", light: RGB(211, 30, 102), dark: RGB(247, 97, 144)),
        Swatch(name: "purple", light: RGB(121, 58, 175), dark: RGB(191, 122, 240)),
        Swatch(name: "cyan", light: RGB(12, 119, 146), dark: RGB(0, 194, 215)),
        Swatch(name: "pink", light: RGB(205, 29, 141), dark: RGB(246, 92, 182)),
        Swatch(name: "indigo", light: RGB(52, 81, 178), dark: RGB(132, 157, 255)),
        Swatch(name: "teal", light: RGB(6, 122, 111), dark: RGB(10, 197, 179)),
    ]

    /// The palette as appearance-aware colors, in slot order. Built once:
    /// every header in the timeline reads it.
    public static let colors: [Color] = swatches.map(color(for:))

    /// The color for a palette slot. An out-of-range slot wraps rather than
    /// trapping, so a caller with a different palette size degrades to a wrong
    /// hue, never a crash.
    public static func color(atSlot slot: Int) -> Color {
        let count = colors.count
        return colors[((slot % count) + count) % count]
    }

    /// An appearance-aware color: AppKit resolves the provider against the
    /// appearance of whatever draws it, so one value serves light and dark.
    private static func color(for swatch: Swatch) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("sender.\(swatch.name)")) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let components = isDark ? swatch.dark : swatch.light
            return NSColor(
                srgbRed: CGFloat(components.red) / 255,
                green: CGFloat(components.green) / 255,
                blue: CGFloat(components.blue) / 255,
                alpha: 1
            )
        })
    }
}
