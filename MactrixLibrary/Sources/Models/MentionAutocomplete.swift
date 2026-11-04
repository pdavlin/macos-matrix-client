import Foundation

/// A room member the mention autocomplete can offer (MATRIX-105).
///
/// The app builds candidates from the member list that `LiveRoom` already
/// holds. No SDK type appears here, so the filter is unit-tested.
public struct MentionCandidate: Hashable, Sendable, UserProfile {
    public let userId: String
    public let displayName: String?
    public let avatarUrl: String?

    public init(userId: String, displayName: String?, avatarUrl: String?) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }

    /// The chip this candidate makes when the user picks it.
    public var target: MentionTarget {
        MentionTarget(userId: userId, displayName: displayName)
    }
}

/// Ranks room members against the text typed after "@".
///
/// Matching ignores case and diacritics. The display name and the user id
/// (without "@") both match. The tiers, best first:
///
/// 1. The display name starts with the query.
/// 2. A word in the display name starts with the query.
/// 3. The user id starts with the query.
/// 4. The display name contains the query.
/// 5. The user id localpart contains the query.
/// 6. The query characters occur in order in the display name or the localpart
///    (fuzzy).
///
/// In one tier, candidates sort by display name, then by user id.
public enum MentionSuggestionFilter {
    /// The most rows the popup shows.
    public static let defaultLimit = 8

    /// The candidates to show for a query.
    ///
    /// - Parameters:
    ///   - query: the text after "@". Empty matches every candidate.
    ///   - candidates: the room members.
    ///   - excludedUserIds: ids to leave out, for example the own user.
    ///   - limit: the most results to return.
    /// - Returns: the best matches, best first, each user one time.
    public static func suggestions(
        for query: String,
        in candidates: [MentionCandidate],
        excluding excludedUserIds: Set<String> = [],
        limit: Int = defaultLimit
    ) -> [MentionCandidate] {
        let needle = normalize(query)
        var seen = excludedUserIds
        var ranked: [Ranked] = []

        for candidate in candidates where seen.insert(candidate.userId).inserted {
            let name = normalize(candidate.displayName ?? "")
            let userId = normalize(String(candidate.userId.drop { $0 == "@" }))
            guard let tier = tier(of: needle, name: name, userId: userId) else { continue }
            ranked.append(Ranked(tier: tier, sortName: name.isEmpty ? userId : name, candidate: candidate))
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                if lhs.sortName != rhs.sortName { return lhs.sortName < rhs.sortName }
                return lhs.candidate.userId < rhs.candidate.userId
            }
            .prefix(max(0, limit))
            .map(\.candidate)
    }

    /// A matched candidate with its sort keys.
    private struct Ranked {
        let tier: Int
        /// The normalized display name, or the user id when the name is empty.
        let sortName: String
        let candidate: MentionCandidate
    }

    /// The match tier, or nil if the candidate does not match.
    ///
    /// - Parameter userId: the normalized user id without "@". Only the
    ///   prefix match reads the server name; the contains and fuzzy matches
    ///   read the localpart, because every member shares a few server names.
    static func tier(of needle: String, name: String, userId: String) -> Int? {
        if needle.isEmpty || name.hasPrefix(needle) { return 0 }
        let words = name.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { $0.hasPrefix(needle) }) { return 1 }
        if userId.hasPrefix(needle) { return 2 }
        if name.contains(needle) { return 3 }
        let localpart = String(userId.prefix { $0 != ":" })
        if localpart.contains(needle) { return 4 }
        if isSubsequence(needle, of: name) || isSubsequence(needle, of: localpart) { return 5 }
        return nil
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}

/// An "@" query that is open in the composer: the "@" and the text the user
/// typed after it, up to the caret.
public struct MentionTrigger: Equatable, Sendable {
    /// The UTF-16 range from the "@" to the caret. A picked chip replaces it.
    public let range: NSRange
    /// The text after the "@".
    public let query: String

    /// The longest query that keeps the popup open.
    public static let maximumQueryLength = 64

    /// The object replacement character, which `NSTextView` stores for each
    /// attachment (each chip).
    public static let attachmentCharacter: unichar = 0xFFFC

    public init(range: NSRange, query: String) {
        self.range = range
        self.query = query
    }

    /// Finds the open "@" query that ends at the caret.
    ///
    /// The "@" must start the text or follow whitespace, a chip, or an
    /// opening bracket or quote, so the "@" in an email address does not open
    /// the popup. The query stops at whitespace and at chips.
    ///
    /// - Parameters:
    ///   - text: the composer text, as `NSTextView.string` gives it.
    ///   - caret: the UTF-16 caret offset. The caller passes nil for a
    ///     selection that is not empty.
    /// - Returns: the trigger, or nil if no "@" query is open.
    public static func find(in text: String, caret: Int?) -> MentionTrigger? {
        guard let caret else { return nil }
        let utf16 = text as NSString
        guard caret >= 1, caret <= utf16.length else { return nil }

        var index = caret - 1
        while index >= 0, caret - index - 1 <= maximumQueryLength {
            let unit = utf16.character(at: index)
            if unit == UInt16(UInt8(ascii: "@")) {
                guard index == 0 || opensQuery(utf16.character(at: index - 1)) else { return nil }
                let range = NSRange(location: index, length: caret - index)
                let query = utf16.substring(with: NSRange(location: index + 1, length: caret - index - 1))
                return MentionTrigger(range: range, query: query)
            }
            if isStop(unit) { return nil }
            index -= 1
        }
        return nil
    }

    /// Whether a UTF-16 unit ends a query (whitespace or a chip).
    static func isStop(_ unit: unichar) -> Bool {
        if unit == attachmentCharacter { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    /// Whether a "@" after this UTF-16 unit opens a query.
    static func opensQuery(_ unit: unichar) -> Bool {
        if isStop(unit) { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return "([{\"'“‘".unicodeScalars.contains(scalar)
    }
}

/// The open autocomplete popup: the query, the rows, and the selected row.
public struct MentionAutocompleteState: Equatable, Sendable {
    public let trigger: MentionTrigger
    public let suggestions: [MentionCandidate]
    public private(set) var selectedIndex: Int

    /// - Returns: nil when no candidate matches, because an empty popup must
    ///   not take Return away from send.
    public init?(trigger: MentionTrigger, suggestions: [MentionCandidate], selectedIndex: Int = 0) {
        guard !suggestions.isEmpty else { return nil }
        self.trigger = trigger
        self.suggestions = suggestions
        self.selectedIndex = min(max(0, selectedIndex), suggestions.count - 1)
    }

    /// The row that Return or Tab picks.
    public var selected: MentionCandidate {
        suggestions[selectedIndex]
    }

    /// Moves the selection by `delta` rows and wraps at both ends.
    public mutating func moveSelection(by delta: Int) {
        let count = suggestions.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }
}

/// A key the open popup handles before the composer does.
public enum MentionAutocompleteKey: Sendable {
    case up
    case down
    /// Return, keypad Enter, or Tab: pick the selected row.
    case confirm
    /// Esc: close the popup for this "@".
    case dismiss
}
