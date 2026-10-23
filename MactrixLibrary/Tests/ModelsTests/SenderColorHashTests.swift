@testable import Models
import Testing

/// MATRIX-68: the sender-color slot, reproduced from Beeper bit for bit.
///
/// Reference hashes were computed two independent ways — the iterative
/// `31 * h + c` loop and the closed form `sum(c[i] * 31^(n-1-i)) mod 2^32`,
/// both reduced to a signed 32-bit value — and agree.
struct SenderColorHashTests {
    @Test
    func matchesJavaStringHashCodeForKnownValues() {
        #expect(SenderColorHash.javaHashCode("") == 0)
        #expect(SenderColorHash.javaHashCode("a") == 97)
        // The value every Java reference quotes.
        #expect(SenderColorHash.javaHashCode("hello") == 99_162_322)
        #expect(SenderColorHash.javaHashCode("@alice:example.org") == 1_983_167_014)
    }

    @Test
    func wrapsOnOverflowInsteadOfTrapping() {
        // Long enough to overflow 32 bits many times over; negative in Java.
        #expect(SenderColorHash.javaHashCode("@grace:example.org") == -725_627_042)
        #expect(SenderColorHash.javaHashCode("@patrick:davlin.io") == -61_076_284)
    }

    @Test
    func hashesUTF16CodeUnitsNotCharacters() {
        // U+1F600 is one Character and two UTF-16 units (D83D DE00):
        // 0xD83D * 31 + 0xDE00 = 1772899.
        #expect(SenderColorHash.javaHashCode("😀") == 1_772_899)
    }

    @Test
    func theInt32MinimumEdgeLandsInSlotZeroLikeJavaScriptMathAbs() {
        // A well-known string whose Java hashCode is Integer.MIN_VALUE. Swift's
        // `abs` on Int32 would trap here; JS `Math.abs` gives 2147483648.
        #expect(SenderColorHash.javaHashCode("polygenelubricants") == Int32.min)
        #expect(SenderColorHash.paletteIndex(forSenderId: "polygenelubricants") == 0)
    }

    @Test
    func paletteIndexIsTheAbsoluteHashModuloEight() {
        #expect(SenderColorHash.paletteSize == 8)
        #expect(SenderColorHash.paletteIndex(forSenderId: "hello") == 2)
        #expect(SenderColorHash.paletteIndex(forSenderId: "@alice:example.org") == 6)
        #expect(SenderColorHash.paletteIndex(forSenderId: "@bob:example.org") == 3)
        // Negative hashes take the absolute value first: -725627042 → slot 2.
        #expect(SenderColorHash.paletteIndex(forSenderId: "@grace:example.org") == 2)
        #expect(SenderColorHash.paletteIndex(forSenderId: "@patrick:davlin.io") == 4)
    }

    @Test
    func paletteIndexIsAlwaysInRange() {
        let senders = ["", "a", "@ada:example.org", "@dev:davlin.io", "😀", "polygenelubricants", String(repeating: "z", count: 500)]
        for sender in senders {
            #expect((0 ..< SenderColorHash.paletteSize).contains(SenderColorHash.paletteIndex(forSenderId: sender)))
        }
    }
}
