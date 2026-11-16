import Foundation

/// The custom emoji of one space that the app saw in message bodies
/// (MATRIX-161), apart from the space's imported image pack.
///
/// The bridge's import is a snapshot, so an emoji that someone adds later is
/// not in the pack. A message that uses it still carries its name and its
/// `mxc://` URL, and that is all the picker and the composer need.
///
/// Rules:
/// - An imported pack entry wins: an emoji whose shortcode the import has is
///   not recorded, and `remove(imported:)` drops it once the import has it.
/// - The same shortcode with a new URL replaces the old entry, and counts as
///   the newest. The same shortcode with the same URL changes nothing.
/// - At most `capacity` entries. The oldest is dropped first.
///
/// Usage:
/// ```swift
/// var learned = LearnedEmoji()
/// if let emoji = LearnedEmoji.emoji(name: ":party:", url: "mxc://example.org/abc") {
///     learned.record(emoji, imported: importedShortcodes)
/// }
/// ```
public struct LearnedEmoji: Equatable, Sendable {
    /// The most entries one space keeps.
    public static let capacity = 500

    /// The entries, oldest first.
    public private(set) var entries: [ImagePackEmoji]
    private var urls: [String: String]

    /// - Parameter entries: Stored entries, oldest first. A shortcode that
    ///   occurs twice keeps its last entry, and the newest `capacity` stay.
    public init(entries: [ImagePackEmoji] = []) {
        self.entries = []
        self.urls = [:]
        for entry in entries {
            record(entry, imported: [])
        }
    }

    /// The emoji for the name and source of a body emoticon, or nil when the
    /// pair cannot be a pack entry.
    ///
    /// - Parameters:
    ///   - name: The emoticon's alt or title, with or without its colons.
    ///   - url: The emoticon's source.
    /// - Returns: Nil when the URL is not `mxc://`, or when the name without
    ///   its colons is empty or holds whitespace, a colon, or a character
    ///   that HTML escapes (the name goes back into an attribute at send).
    public static func emoji(name: String, url: String) -> ImagePackEmoji? {
        guard ImagePack.isImageKey(url) else { return nil }
        var shortcode = Substring(name.trimmingCharacters(in: .whitespacesAndNewlines))
        if shortcode.count >= 2, shortcode.hasPrefix(":"), shortcode.hasSuffix(":") {
            shortcode = shortcode.dropFirst().dropLast()
        }
        guard !shortcode.isEmpty, !shortcode.contains(where: isRefused) else { return nil }
        return ImagePackEmoji(shortcode: String(shortcode), url: url)
    }

    private static func isRefused(_ character: Character) -> Bool {
        character.isWhitespace || ":&<>\"'".contains(character)
    }

    /// Records an emoji that a message body showed.
    ///
    /// - Parameters:
    ///   - emoji: The emoji.
    ///   - imported: The shortcodes of the space's imported packs.
    /// - Returns: Whether the set changed.
    @discardableResult
    public mutating func record(_ emoji: ImagePackEmoji, imported: Set<String>) -> Bool {
        guard !imported.contains(emoji.shortcode), urls[emoji.shortcode] != emoji.url else { return false }
        if urls[emoji.shortcode] != nil {
            entries.removeAll { $0.shortcode == emoji.shortcode }
        }
        urls[emoji.shortcode] = emoji.url
        entries.append(emoji)
        let excess = entries.count - Self.capacity
        if excess > 0 {
            for dropped in entries.prefix(excess) {
                urls[dropped.shortcode] = nil
            }
            entries.removeFirst(excess)
        }
        return true
    }

    /// Drops the entries that the import now has.
    ///
    /// - Parameter imported: The shortcodes of the space's imported packs.
    /// - Returns: Whether the set changed.
    @discardableResult
    public mutating func remove(imported: Set<String>) -> Bool {
        let kept = entries.filter { !imported.contains($0.shortcode) }
        guard kept.count != entries.count else { return false }
        for entry in entries where imported.contains(entry.shortcode) {
            urls[entry.shortcode] = nil
        }
        entries = kept
        return true
    }
}

public extension ImagePack {
    /// The key of the pack that holds a space's learned emoji when the space
    /// has no imported pack. Not a state key: the pack is never written.
    static let learnedKey = "io.davlin.matrixclient.learned"

    /// The packs that the picker and the composer show for one space: the
    /// imported packs, with the learned emoji in the first one, in shortcode
    /// order. A space with learned emoji and no import gets one pack.
    ///
    /// - Parameters:
    ///   - learned: The learned emoji of the space. None of them has a
    ///     shortcode of `imported` (`LearnedEmoji` keeps that rule).
    ///   - imported: The packs from the space's state.
    ///   - name: The space's name, the title of the lone learned pack.
    static func merging(learned: [ImagePackEmoji], into imported: [ImagePack], fallbackName name: String?) -> [ImagePack] {
        guard !learned.isEmpty else { return imported }
        guard let first = imported.first else {
            return [ImagePack(key: learnedKey, displayName: nil, emoji: learned.sorted(by: inShortcodeOrder)).named(fallback: name)]
        }
        let merged = ImagePack(
            key: first.key,
            displayName: first.displayName,
            emoji: (first.emoji + learned).sorted(by: inShortcodeOrder)
        )
        return [merged] + imported.dropFirst()
    }

    /// The order of the emoji in a pack: by shortcode, lower case first.
    internal static func inShortcodeOrder(_ lhs: ImagePackEmoji, _ rhs: ImagePackEmoji) -> Bool {
        (lhs.shortcode.lowercased(), lhs.shortcode) < (rhs.shortcode.lowercased(), rhs.shortcode)
    }
}
