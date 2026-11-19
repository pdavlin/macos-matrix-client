#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif
import SwiftUI

/// Colors and metrics of the bridge-network badge on a chat avatar
/// (MATRIX-194).
///
/// The badge is a letter-circle SF Symbol (`ChatListNetwork.badgeSymbolName`)
/// with a white letter on a network tint. The tints are this project's own:
/// each reads as its network's hue family, but none is a brand palette
/// value. Each tint has a dark variant that is lighter and more saturated,
/// so the badge keeps its weight on a dark sidebar. The colors are defined
/// in code, not in the asset catalog: named asset colors do not resolve
/// inside this package or its snapshot tests.
///
/// The badge carries no glass: it is an opaque mark on the avatar.
public enum NetworkBadgeToken {
    /// One badge tint, with a light and a dark variant (`0xRRGGBB`).
    public struct Tint: Hashable, Sendable {
        public let light: UInt32
        public let dark: UInt32

        /// The tint for the current appearance. It resolves when the badge
        /// draws.
        public var color: Color {
            let light = light
            let dark = dark
            #if canImport(AppKit)
                return Color(nsColor: NSColor(name: nil) { appearance in
                    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    return NSColor(rgb: isDark ? dark : light)
                })
            #else
                return Color(uiColor: UIColor { traits in
                    UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
                })
            #endif
        }
    }

    // MARK: Tints

    public static let slack = Tint(light: 0x6A2C70, dark: 0xA63AC2)
    public static let whatsApp = Tint(light: 0x1E8E4E, dark: 0x1CC766)
    public static let signal = Tint(light: 0x2E5FC7, dark: 0x4F86FF)
    public static let discord = Tint(light: 0x4F52C9, dark: 0x7377FF)
    public static let telegram = Tint(light: 0x1B85BF, dark: 0x2FAEF2)
    public static let googleChat = Tint(light: 0x1E7A3C, dark: 0x1ABD52)
    public static let groupMe = Tint(light: 0x0E86B0, dark: 0x10BDF7)
    public static let meta = Tint(light: 0x3A50B8, dark: 0x5C78FF)
    public static let instagram = Tint(light: 0xB8325F, dark: 0xF0457F)
    public static let messenger = Tint(light: 0x6145C8, dark: 0x8A6CFF)
    public static let googleMessages = Tint(light: 0x1F6E9C, dark: 0x2C9EE0)
    public static let linkedIn = Tint(light: 0x22578C, dark: 0x3A86D6)
    public static let twitter = Tint(light: 0x2B2D33, dark: 0x737C94)

    /// Every tint, for the token tests.
    public static let all: [Tint] = [
        slack, whatsApp, signal, discord, telegram, googleChat, groupMe,
        meta, instagram, messenger, googleMessages, linkedIn, twitter,
    ]

    /// The letter's color on every tint.
    public static let glyphColor = Color.white

    // MARK: Cut-out ring

    /// Width of the transparent ring cut out of the avatar around the badge,
    /// as a fraction of the badge's side: 1.6 pt on a 36 pt row avatar, 2 pt
    /// on a 44 pt pinned tile. The ring lets the badge read on any avatar.
    public static let ringWidthRatio: CGFloat = 0.12

    /// The ring width for a badge of the given side.
    ///
    /// - Parameter badgeSize: the badge's side in points.
    /// - Returns: `badgeSize * ringWidthRatio`.
    public static func ringWidth(forBadgeSize badgeSize: CGFloat) -> CGFloat {
        badgeSize * ringWidthRatio
    }
}
