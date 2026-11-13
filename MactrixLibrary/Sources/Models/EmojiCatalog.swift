import Foundation

/// Every emoji the reaction picker offers, grouped by category, with English
/// CLDR names for search (MATRIX-111, M2-B4, D-3).
///
/// The data is Unicode's emoji-test.txt (Emoji 15.1), which
/// `scripts/generate-emoji-data.py` turns into the bundled `Emoji.txt` of the
/// UI target. It holds fully-qualified emoji only, with no skin-tone
/// variants: M2 offers the default (yellow) emoji only.
///
/// A value type with no bundle access, so parsing and search run in unit tests
/// from a small fixture. `UI.EmojiCatalog.bundled` loads the real file.
///
/// Usage:
/// ```swift
/// let catalog = EmojiCatalog.parse(text)
/// let matches = catalog.search("thumbs") // 👍, 👎
/// ```
public struct EmojiCatalog: Equatable, Sendable {
    /// One emoji and its search data.
    public struct Entry: Hashable, Identifiable, Sendable {
        /// The emoji itself, the string a reaction sends.
        public let value: String
        /// The CLDR English short name, for example "thumbs up".
        public let name: String
        /// The Unicode group, for example "People & Body".
        public let group: String
        /// The Unicode subgroup, for example "hand-fingers-closed".
        public let subgroup: String

        /// The folded words of `name`, for search.
        let nameWords: [String]
        /// `nameWords` joined by single spaces.
        let foldedName: String
        /// The folded words of the subgroup and the group. A query that
        /// matches only these ranks below every name match.
        let keywords: [String]

        /// `value` for a Unicode emoji. An image-pack emoji has an id of its
        /// own (`ImagePackSection`), because two shortcodes can share one image.
        public let id: String

        /// Whether the entry is a custom emoji: `value` is an `mxc://` URI
        /// and `name` is the shortcode.
        public var isImage: Bool {
            ImagePack.isImageKey(value)
        }

        public init(value: String, name: String, group: String, subgroup: String) {
            self.init(id: value, value: value, name: name, group: group, subgroup: subgroup)
        }

        init(id: String, value: String, name: String, group: String, subgroup: String) {
            self.id = id
            self.value = value
            self.name = name
            self.group = group
            self.subgroup = subgroup
            let words = EmojiCatalog.words(in: name)
            self.nameWords = words
            self.foldedName = words.joined(separator: " ")
            self.keywords = EmojiCatalog.words(in: subgroup) + EmojiCatalog.words(in: group)
        }
    }

    /// One Unicode group, for example "Smileys & Emotion".
    public struct Category: Hashable, Identifiable, Sendable {
        public let name: String
        public let entries: [Entry]

        public var id: String {
            name
        }

        public init(name: String, entries: [Entry]) {
            self.name = name
            self.entries = entries
        }
    }

    /// The categories in CLDR order.
    public let categories: [Category]
    /// Every entry in CLDR order.
    public let entries: [Entry]

    public init(categories: [Category]) {
        self.categories = categories
        self.entries = categories.flatMap(\.entries)
    }

    // MARK: - Parsing

    /// Reads the line format that `scripts/generate-emoji-data.py` writes.
    ///
    /// Each line is a comment (`# …`), a group (`G<TAB>name`), a subgroup
    /// (`S<TAB>name`), or an emoji (`<emoji><TAB><name>`). An emoji belongs to
    /// the last group and subgroup above it. Lines that do not fit are skipped.
    ///
    /// - Parameter text: The file contents.
    /// - Returns: The catalog. Empty groups are left out.
    public static func parse(_ text: String) -> EmojiCatalog {
        var categories: [Category] = []
        var groupName: String?
        var subgroupName = ""
        var groupEntries: [Entry] = []

        func closeGroup() {
            if let groupName, !groupEntries.isEmpty {
                categories.append(Category(name: groupName, entries: groupEntries))
            }
            groupEntries = []
        }

        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("# ") { continue }
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, !fields[0].isEmpty, !fields[1].isEmpty else { continue }
            let tag = String(fields[0])
            let value = String(fields[1])

            switch tag {
            case "G":
                closeGroup()
                groupName = value
                subgroupName = ""
            case "S":
                subgroupName = value
            default:
                guard let groupName else { continue }
                groupEntries.append(Entry(value: tag, name: value, group: groupName, subgroup: subgroupName))
            }
        }
        closeGroup()
        return EmojiCatalog(categories: categories)
    }

    // MARK: - Search

    /// The entries that match `query`, best match first.
    ///
    /// Every word of the query must start a word of the emoji's name or of
    /// its keywords (subgroup and group). Case and diacritics do not matter.
    /// The ranks, each in CLDR order:
    /// 1. the name is the query ("thumbs up");
    /// 2. the name starts with the query ("thumbs");
    /// 3. every query word starts a name word ("up thumbs");
    /// 4. a query word matches a keyword only ("fingers" for 👍).
    ///
    /// - Parameter query: The search text. Blank text matches nothing.
    /// - Returns: The matching entries.
    public func search(_ query: String) -> [Entry] {
        let tokens = Self.words(in: query)
        guard !tokens.isEmpty else { return [] }
        let foldedQuery = tokens.joined(separator: " ")

        var ranked: [[Entry]] = Array(repeating: [], count: 4)
        for entry in entries {
            if let rank = Self.rank(of: entry, foldedQuery: foldedQuery, tokens: tokens) {
                ranked[rank].append(entry)
            }
        }
        return Array(ranked.joined())
    }

    /// The entry for an emoji string, if the catalog has it.
    public func entry(for value: String) -> Entry? {
        entries.first { $0.value == value }
    }

    /// The rank of `entry` for a query (0 is best), or nil if it does not
    /// match.
    static func rank(of entry: Entry, foldedQuery: String, tokens: [String]) -> Int? {
        if entry.foldedName == foldedQuery { return 0 }
        if entry.foldedName.hasPrefix(foldedQuery) { return 1 }
        let startsNameWord = { (token: String) -> Bool in entry.nameWords.contains { $0.hasPrefix(token) } }
        if tokens.allSatisfy(startsNameWord) { return 2 }
        let startsAnyWord = { (token: String) -> Bool in
            startsNameWord(token) || entry.keywords.contains { $0.hasPrefix(token) }
        }
        if tokens.allSatisfy(startsAnyWord) { return 3 }
        return nil
    }

    /// Lowercased, diacritic-free words: runs of letters and digits.
    static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
