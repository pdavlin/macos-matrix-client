import Foundation
import Testing
@testable import Tokens

/// MATRIX-194: the network badge tints and the cut-out ring.
struct NetworkBadgeTokenTests {
    /// HSL lightness and saturation of one `0xRRGGBB` color, each 0...1.
    private func lightnessAndSaturation(_ rgb: UInt32) -> (lightness: Double, saturation: Double) {
        let red = Double((rgb >> 16) & 0xFF) / 255
        let green = Double((rgb >> 8) & 0xFF) / 255
        let blue = Double(rgb & 0xFF) / 255
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let lightness = (high + low) / 2
        guard high > low else { return (lightness, 0) }
        let saturation = (high - low) / (1 - abs(2 * lightness - 1))
        return (lightness, saturation)
    }

    /// Each dark variant is lighter and more saturated than its light one.
    @Test(arguments: NetworkBadgeToken.all)
    func darkVariantIsLighterAndMoreSaturated(tint: NetworkBadgeToken.Tint) {
        let light = lightnessAndSaturation(tint.light)
        let dark = lightnessAndSaturation(tint.dark)
        #expect(dark.lightness > light.lightness)
        #expect(dark.saturation > light.saturation)
    }

    @Test
    func tintsAreDistinct() {
        #expect(Set(NetworkBadgeToken.all).count == NetworkBadgeToken.all.count)
    }

    @Test
    func ringScalesWithTheBadge() {
        #expect(abs(NetworkBadgeToken.ringWidth(forBadgeSize: 13.5) - 1.62) < 0.001)
        #expect(abs(NetworkBadgeToken.ringWidth(forBadgeSize: 16.5) - 1.98) < 0.001)
    }
}
