import Testing
@testable import Tokens

/// Pins the MATRIX-68 conversation-rhythm values and the sender palette.
/// Both are Beeper's numbers; a change here is a design decision, not a fix.
@Suite("Rhythm and sender-color tokens")
struct RhythmTokenTests {
    @Test
    func gapValuesArePinned() {
        #expect(RhythmToken.noGap == 0)
        #expect(RhythmToken.sameSenderBurstGap == 2)
        #expect(RhythmToken.senderTurnGap == 4)
        #expect(RhythmToken.shortPauseGap == 4)
        #expect(RhythmToken.pauseGap == 13)
        #expect(RhythmToken.longPauseGap == 26)
    }

    @Test
    func paletteIsBeepersEightSlotsInOrder() {
        let names = SenderColorToken.swatches.map(\.name)
        #expect(names == ["grass", "amber", "crimson", "purple", "cyan", "pink", "indigo", "teal"])
        #expect(SenderColorToken.colors.count == 8)

        let grass = SenderColorToken.swatches[0]
        #expect(grass.light == SenderColorToken.RGB(41, 124, 59))
        #expect(grass.dark == SenderColorToken.RGB(99, 193, 116))
        let teal = SenderColorToken.swatches[7]
        #expect(teal.light == SenderColorToken.RGB(6, 122, 111))
        #expect(teal.dark == SenderColorToken.RGB(10, 197, 179))
    }

    @Test
    func anOutOfRangeSlotWrapsInsteadOfTrapping() {
        #expect(SenderColorToken.color(atSlot: 8) == SenderColorToken.color(atSlot: 0))
        #expect(SenderColorToken.color(atSlot: -1) == SenderColorToken.color(atSlot: 7))
    }
}
