import Foundation

/// Which palette slot a sender's name draws in (MATRIX-68).
///
/// Beeper's rule, reproduced bit for bit so a sender keeps the color a Beeper
/// user knows them by: `abs(javaHash(senderId)) % 8`. The palette itself is a
/// design token (`SenderColorToken`); this type only picks the slot.
public enum SenderColorHash {
    /// Number of slots in the sender palette.
    public static let paletteSize = 8

    /// Java's `String.hashCode`: `h = 31 * h + c` over the UTF-16 code units,
    /// in a 32-bit signed integer that wraps on overflow.
    ///
    /// UTF-16 code units, not characters or scalars: an astral-plane character
    /// is two units in Java and in JavaScript, and both units are hashed.
    public static func javaHashCode(_ string: String) -> Int32 {
        var hash: Int32 = 0
        for unit in string.utf16 {
            hash = 31 &* hash &+ Int32(unit)
        }
        return hash
    }

    /// The palette slot for a sender ID, in `0 ..< paletteSize`.
    ///
    /// The absolute value is taken in a wider type, the way JavaScript's
    /// `Math.abs` sees a 32-bit integer: `abs(Int32.min)` is 2147483648 there,
    /// slot 0, where Swift's `abs` on `Int32` would trap.
    public static func paletteIndex(forSenderId senderId: String) -> Int {
        Int(javaHashCode(senderId).magnitude % UInt32(paletteSize))
    }
}
