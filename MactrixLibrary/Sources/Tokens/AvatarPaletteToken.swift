import SwiftUI

/// The fills behind avatar initials (MATRIX-129).
///
/// Sixteen two-stop vertical gradients, lighter at the top. The palette is
/// our own: each stop was solved for a hue so that white text has a WCAG
/// contrast of at least 3.2:1 on the top stop and 4.6:1 on the bottom stop.
/// The fill does not change with the appearance; white initials on a
/// mid-dark color read on a light or a dark sidebar.
///
/// The slot comes from `Models.AvatarColorHash` (FNV-1a of the user ID or
/// room ID). Its `paletteSize` must equal `gradients.count`; a token test
/// pins both at 16.
public enum AvatarPaletteToken {
    /// One palette slot: the colors at the top and the bottom of the circle.
    public struct Swatch: Equatable, Sendable {
        public let name: String
        public let top: SenderColorToken.RGB
        public let bottom: SenderColorToken.RGB

        public init(name: String, top: SenderColorToken.RGB, bottom: SenderColorToken.RGB) {
            self.name = name
            self.top = top
            self.bottom = bottom
        }
    }

    /// The palette, in slot order. Do not reorder: a slot change recolors
    /// every avatar.
    public static let gradients: [Swatch] = [
        Swatch(name: "red", top: .init(235, 99, 108), bottom: .init(215, 59, 47)),
        Swatch(name: "coral", top: .init(215, 116, 91), bottom: .init(186, 89, 41)),
        Swatch(name: "orange", top: .init(193, 129, 81), bottom: .init(159, 106, 35)),
        Swatch(name: "amber", top: .init(175, 138, 74), bottom: .init(140, 114, 31)),
        Swatch(name: "lime", top: .init(98, 159, 67), bottom: .init(50, 134, 30)),
        Swatch(name: "green", top: .init(68, 161, 91), bottom: .init(30, 134, 70)),
        Swatch(name: "emerald", top: .init(67, 159, 126), bottom: .init(29, 131, 108)),
        Swatch(name: "teal", top: .init(66, 157, 151), bottom: .init(30, 129, 137)),
        Swatch(name: "cyan", top: .init(73, 154, 175), bottom: .init(37, 124, 168)),
        Swatch(name: "sky", top: .init(83, 150, 198), bottom: .init(45, 117, 206)),
        Swatch(name: "blue", top: .init(95, 143, 227), bottom: .init(56, 103, 255)),
        Swatch(name: "indigo", top: .init(107, 119, 255), bottom: .init(66, 56, 255)),
        Swatch(name: "violet", top: .init(144, 107, 255), bottom: .init(132, 56, 255)),
        Swatch(name: "purple", top: .init(189, 105, 249), bottom: .init(180, 51, 230)),
        Swatch(name: "magenta", top: .init(218, 92, 218), bottom: .init(202, 45, 181)),
        Swatch(name: "pink", top: .init(228, 96, 167), bottom: .init(215, 47, 115)),
    ]

    /// The initials text color on every gradient.
    public static let textColor = Color.white

    /// The gradient for a palette slot, top to bottom. An out-of-range slot
    /// wraps rather than trapping, so a palette-size mismatch degrades to a
    /// wrong hue, never a crash.
    public static func gradient(atSlot slot: Int) -> LinearGradient {
        let count = gradients.count
        let entry = gradients[((slot % count) + count) % count]
        return LinearGradient(colors: [color(entry.top), color(entry.bottom)], startPoint: .top, endPoint: .bottom)
    }

    private static func color(_ rgb: SenderColorToken.RGB) -> Color {
        Color(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}
