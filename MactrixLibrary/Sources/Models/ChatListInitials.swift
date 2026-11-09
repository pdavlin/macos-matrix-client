import Foundation

/// Which avatar-palette slot an ID draws in (MATRIX-129).
///
/// The slot is the FNV-1a 32-bit hash of the ID's UTF-8 bytes, modulo the
/// palette size. FNV-1a is fixed by its spec, so a person or room keeps one
/// color across launches, machines, and Swift versions. Swift's `hashValue`
/// is seeded per process and must never pick a color. The palette itself is
/// a design token (`AvatarPaletteToken`); this type only picks the slot.
public enum AvatarColorHash {
    /// Number of gradients in `AvatarPaletteToken.gradients`.
    public static let paletteSize = 16

    /// The FNV-1a 32-bit offset basis.
    static let offsetBasis: UInt32 = 2_166_136_261

    /// The FNV-1a 32-bit prime.
    static let prime: UInt32 = 16_777_619

    /// The FNV-1a 32-bit hash of the string's UTF-8 bytes: for each byte,
    /// XOR it into the hash, then multiply by the prime with wrap-around.
    ///
    /// ```swift
    /// AvatarColorHash.fnv1a32("a") // 0xE40C292C
    /// ```
    public static func fnv1a32(_ string: String) -> UInt32 {
        var hash = offsetBasis
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* prime
        }
        return hash
    }

    /// The palette slot for a user ID or room ID, in `0 ..< paletteSize`.
    ///
    /// - Parameter id: a full Matrix user ID (`@alice:example.org`) for a
    ///   person, or a room ID (`!abc:example.org`) for a room.
    public static func paletteIndex(forId id: String) -> Int {
        Int(fnv1a32(id) % UInt32(paletteSize))
    }
}

/// The letters and color of an avatar with no image (MATRIX-129).
public struct ChatListInitials: Equatable, Sendable {
    /// One or two uppercased letters, or "#" when the name has no letter.
    public var text: String
    /// The `AvatarPaletteToken` slot, from `AvatarColorHash`.
    public var paletteIndex: Int

    public init(text: String, paletteIndex: Int) {
        self.text = text
        self.paletteIndex = paletteIndex
    }

    /// The initials of a person: up to two letters, colored by user ID.
    ///
    /// - Parameters:
    ///   - displayName: the person's display name, when known.
    ///   - userId: the person's full Matrix user ID. It picks the color and,
    ///     when the name has no letter, the fallback letter.
    public static func person(displayName: String?, userId: String) -> ChatListInitials {
        ChatListInitials(
            text: personText(displayName: displayName, userId: userId),
            paletteIndex: AvatarColorHash.paletteIndex(forId: userId)
        )
    }

    /// The initial of a room: one letter or digit, colored by room ID.
    ///
    /// - Parameters:
    ///   - title: the room's display name.
    ///   - roomId: the room ID. It picks the color.
    public static func room(title: String, roomId: String) -> ChatListInitials {
        ChatListInitials(text: roomText(title: title), paletteIndex: AvatarColorHash.paletteIndex(forId: roomId))
    }

    /// The letters for a person.
    ///
    /// Takes the first letter of each of the first two words that contain a
    /// letter. A word is a run of characters between whitespace. Only Unicode
    /// letters count, so "(WhatsApp)" gives "W" and an emoji gives nothing.
    /// With no letter in the name, the result is the first letter of the user
    /// ID's localpart, else "#". The result is uppercased.
    ///
    /// ```swift
    /// ChatListInitials.personText(displayName: "Seth Redacted (WhatsApp)", userId: "@seth:example.org") // "SR"
    /// ChatListInitials.personText(displayName: nil, userId: "@_bob:example.org") // "B"
    /// ChatListInitials.personText(displayName: "🎉", userId: "@123:example.org") // "#"
    /// ```
    public static func personText(displayName: String?, userId: String) -> String {
        let words = (displayName ?? "").split(whereSeparator: \.isWhitespace)
        let letters = words.lazy.compactMap { (word: Substring) -> Character? in
            word.first(where: \.isLetter)
        }
        let initials = letters.prefix(2).map { (letter: Character) -> String in
            String(letter).uppercased()
        }
        if !initials.isEmpty {
            return initials.joined()
        }
        if let letter = ChatListSender.localpart(of: userId).first(where: \.isLetter) {
            return String(letter).uppercased()
        }
        return "#"
    }

    /// The letter for a room: the title's first letter or digit, uppercased,
    /// else "#". The rule from MATRIX-67, unchanged.
    public static func roomText(title: String) -> String {
        title.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "#"
    }
}
