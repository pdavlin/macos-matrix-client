import Foundation
import Testing
@testable import Tokens

/// MATRIX-129: the avatar palette and the bubble-cluster slots.
struct AvatarTokenTests {
    @Test
    func paletteHasSixteenNamedGradients() {
        // Must equal `Models.AvatarColorHash.paletteSize`.
        #expect(AvatarPaletteToken.gradients.count == 16)
        #expect(Set(AvatarPaletteToken.gradients.map(\.name)).count == 16)
    }

    /// WCAG relative luminance of one sRGB color.
    private func luminance(_ rgb: SenderColorToken.RGB) -> Double {
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    @Test
    func whiteInitialsHaveEnoughContrastOnEveryStop() {
        for swatch in AvatarPaletteToken.gradients {
            let topContrast = 1.05 / (luminance(swatch.top) + 0.05)
            let bottomContrast = 1.05 / (luminance(swatch.bottom) + 0.05)
            #expect(topContrast >= 3.0, "\(swatch.name) top contrast \(topContrast)")
            #expect(bottomContrast >= 4.5, "\(swatch.name) bottom contrast \(bottomContrast)")
            #expect(luminance(swatch.top) > luminance(swatch.bottom), "\(swatch.name) must be lighter at the top")
        }
    }

    @Test
    func clusterSlotsMatchTheSpecAndStayInsideTheSquare() {
        let slots = ChatListToken.clusterSlots
        #expect(slots.count == 5)
        #expect(slots.map(\.scale) == [0.48, 0.35, 0.27, 0.215, 0.20])
        for slot in slots {
            let radius = slot.scale / 2
            #expect(abs(slot.offsetX) + radius <= 0.5)
            #expect(abs(slot.offsetY) + radius <= 0.5)
        }
    }

    @Test
    func clusterBubblesDoNotOverlap() {
        let slots = ChatListToken.clusterSlots
        for first in slots.indices {
            for second in slots.indices where second > first {
                let deltaX = slots[first].offsetX - slots[second].offsetX
                let deltaY = slots[first].offsetY - slots[second].offsetY
                let distance = (deltaX * deltaX + deltaY * deltaY).squareRoot()
                #expect(distance >= (slots[first].scale + slots[second].scale) / 2, "slots \(first) and \(second) overlap")
            }
        }
    }

    @Test
    func networkBadgeScalesWithTheAvatar() {
        #expect(ChatListToken.networkBadgeSize(forAvatarSize: ChatListToken.avatarSize) == 13.5)
        #expect(ChatListToken.networkBadgeSize(forAvatarSize: ChatListToken.pinnedAvatarSize) == 16.5)
    }

    @Test
    func rowsDrawTheCompactClusterAndPinnedTilesTheFullOne() {
        #expect(ChatListToken.avatarSize < ChatListToken.clusterFullModeMinimumSize)
        #expect(ChatListToken.pinnedAvatarSize >= ChatListToken.clusterFullModeMinimumSize)
    }
}
