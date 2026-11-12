import Foundation

// MARK: - Candidates and results (MATRIX-114, D-7a)

/// A room the ⌘K quick switcher can offer.
///
/// Built in Core from the SDK room list. A value type, so ranking and the
/// switcher view are testable without the SDK.
public struct QuickSwitcherRoom: Hashable, Identifiable, Sendable {
    /// The room ID.
    public let id: String
    /// The room's display name, as the sidebar shows it.
    public let name: String
    /// The room's canonical alias (`#room:server`), if it has one.
    public let canonicalAlias: String?
    public let avatarUrl: String?
    public let isDirect: Bool
    /// The other member of a direct-message room, if known. People search
    /// results with this user ID are not shown again as person rows.
    public let directUserId: String?
    /// The room's place in the SDK room list, which sorts by recent
    /// activity: 0 is the most recent.
    public let recencyRank: Int
    /// What tells the room from another one with the same name (MATRIX-147),
    /// for example "Slack • DevObsessed". Shown after the name. Nil shows
    /// the alias.
    public var detail: String?
    /// The room's bridged network (`ChatListNetwork.detect`), or nil.
    public var network: ChatListNetwork?

    public init(
        id: String,
        name: String,
        canonicalAlias: String? = nil,
        avatarUrl: String? = nil,
        isDirect: Bool = false,
        directUserId: String? = nil,
        recencyRank: Int,
        detail: String? = nil,
        network: ChatListNetwork? = nil
    ) {
        self.id = id
        self.name = name
        self.canonicalAlias = canonicalAlias
        self.avatarUrl = avatarUrl
        self.isDirect = isDirect
        self.directUserId = directUserId
        self.recencyRank = recencyRank
        self.detail = detail
        self.network = network
    }
}

/// One row in the quick switcher.
public enum QuickSwitcherResult: Hashable, Identifiable, Sendable {
    case room(QuickSwitcherRoom)
    case person(NewChatPerson)

    /// Prefixed, so a room ID and a user ID can never collide.
    public var id: String {
        switch self {
        case let .room(room): "room:\(room.id)"
        case let .person(person): "person:\(person.userId)"
        }
    }

    /// Whether the row is a room, for the switcher's Rooms section.
    public var isRoom: Bool {
        if case .room = self { return true }
        return false
    }
}

/// What the quick switcher is for.
public enum QuickSwitcherMode: Hashable, Sendable {
    /// ⌘K: open the picked room, or the DM with the picked person.
    case navigate
    /// Return a room to a caller (MATRIX-112 forward). Rooms only: the
    /// directory search does not run and person rows never show.
    case pickRoom
}

/// The key that activated a row.
public enum QuickSwitcherActivationKey: Hashable, Sendable {
    /// Return, or a click.
    case primary
    /// ⌥-Return. Reserved for "open in new window" (MATRIX-116, D-8).
    case alternate
}

/// The step the app takes for an activated row.
public enum QuickSwitcherDecision: Hashable, Sendable {
    /// Show the room in this window.
    case openRoom(roomId: String)
    /// Show the room in a window of its own (MATRIX-116).
    case openRoomInNewWindow(roomId: String)
    /// Open the existing DM with the person, or create one.
    case startDirectChat(userId: String)
    /// Hand the room back to the caller (picker mode).
    case pickRoom(roomId: String)
    /// Do nothing.
    case ignore
}

// MARK: - Fuzzy scoring

/// Case- and diacritic-insensitive fuzzy matching for the quick switcher.
///
/// Matches fall into tiers, so the order is easy to predict: an exact match
/// beats a prefix, a prefix beats a word start, a word start beats a
/// substring, and a substring beats a scattered subsequence. Inside a tier,
/// shorter candidates and tighter subsequences score higher.
public enum QuickSwitcherFuzzy {
    static let exactScore = 1000
    static let prefixScore = 800
    static let wordStartScore = 600
    static let substringScore = 400
    static let subsequenceScore = 100

    /// The score of `query` against `candidate`, or `nil` if every query
    /// character does not occur in the candidate, in order.
    ///
    /// - Parameters:
    ///   - query: the typed text. Whitespace at either end is ignored.
    ///   - candidate: a room name, an alias, or a user ID.
    /// - Returns: a positive score, higher for a better match, or `nil`.
    ///
    /// ```swift
    /// QuickSwitcherFuzzy.score(query: "eng", candidate: "Engineering")  // prefix tier
    /// QuickSwitcherFuzzy.score(query: "egn", candidate: "Engineering")  // subsequence tier
    /// QuickSwitcherFuzzy.score(query: "xyz", candidate: "Engineering")  // nil
    /// ```
    public static func score(query: String, candidate: String) -> Int? {
        let needle = Array(normalize(query.trimmingCharacters(in: .whitespacesAndNewlines)))
        let haystack = Array(normalize(candidate))
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }

        // A short candidate scores a little higher than a long one in the same tier.
        let lengthPenalty = min(haystack.count - needle.count, 99)

        if needle == haystack {
            return exactScore
        }
        if haystack.starts(with: needle) {
            return prefixScore - lengthPenalty
        }
        let starts = occurrences(of: needle, in: haystack)
        if !starts.isEmpty {
            let tier = starts.contains { isWordStart($0, in: haystack) } ? wordStartScore : substringScore
            return tier - lengthPenalty
        }
        return subsequence(needle, in: haystack)
    }

    /// Lowercased, with accents removed, so "cafe" finds "Café".
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// A position starts a word if it is the first character, or the
    /// character before it is not a letter or digit (space, `#`, `@`, `:`,
    /// `-`, `_`, `.`).
    static func isWordStart(_ index: Int, in haystack: [Character]) -> Bool {
        index == 0 || !(haystack[index - 1].isLetter || haystack[index - 1].isNumber)
    }

    private static func occurrences(of needle: [Character], in haystack: [Character]) -> [Int] {
        guard needle.count <= haystack.count else { return [] }
        return (0 ... haystack.count - needle.count).filter { start in
            haystack[start ..< start + needle.count].elementsEqual(needle)
        }
    }

    /// A greedy, left-to-right subsequence match. Each matched character at
    /// a word start or right after the previous match adds to the score;
    /// each skipped character between matches takes one point away.
    private static func subsequence(_ needle: [Character], in haystack: [Character]) -> Int? {
        var score = subsequenceScore
        var needleIndex = 0
        var previousMatch: Int?

        for (index, character) in haystack.enumerated() where needleIndex < needle.count {
            guard character == needle[needleIndex] else { continue }
            if isWordStart(index, in: haystack) { score += 10 }
            if let previousMatch {
                if previousMatch == index - 1 {
                    score += 5
                } else {
                    score -= index - previousMatch - 1
                }
            }
            previousMatch = index
            needleIndex += 1
        }

        guard needleIndex == needle.count else { return nil }
        // Never let a scattered match fall out of its tier.
        return max(score, 1)
    }
}

// MARK: - Ranking and merging

/// Turns the room list and the directory results into quick switcher rows.
public enum QuickSwitcherRanking {
    /// The most rooms the switcher lists.
    public static let defaultRoomLimit = 20

    /// An alias or a DM partner's user ID match counts a little less than
    /// the same match on the name, so the name wins a tie.
    static let secondaryFieldPenalty = 50

    /// The best score of `query` over a room's name, alias, and DM partner.
    ///
    /// - Returns: the score, or `nil` if no field matches.
    public static func score(query: String, room: QuickSwitcherRoom) -> Int? {
        let nameScore = QuickSwitcherFuzzy.score(query: query, candidate: room.name)
        let secondaryScores = [room.canonicalAlias, room.directUserId]
            .compactMap(\.self)
            .compactMap { QuickSwitcherFuzzy.score(query: query, candidate: $0) }
            .map { $0 - secondaryFieldPenalty }
        return ([nameScore].compactMap(\.self) + secondaryScores).max()
    }

    /// The rooms to list for `query`, best first.
    ///
    /// - Parameters:
    ///   - rooms: every room the switcher can offer, in any order.
    ///   - query: the typed text.
    ///   - currentRoomId: the room the window shows. With an empty query it
    ///     moves to the end, because switching to it does nothing.
    ///   - limit: the most rooms to return.
    /// - Returns: with an empty query, the most recent rooms. Otherwise the
    ///   matching rooms by score, ties broken by recency.
    public static func rankRooms(
        _ rooms: [QuickSwitcherRoom],
        query: String,
        currentRoomId: String?,
        limit: Int = defaultRoomLimit
    ) -> [QuickSwitcherRoom] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            let byRecency = rooms.sorted { lhs, rhs in
                let lhsIsCurrent = lhs.id == currentRoomId
                let rhsIsCurrent = rhs.id == currentRoomId
                if lhsIsCurrent != rhsIsCurrent { return rhsIsCurrent }
                return lhs.recencyRank < rhs.recencyRank
            }
            return Array(byRecency.prefix(limit))
        }

        let scored = rooms.compactMap { room in
            score(query: trimmed, room: room).map { (room: room, score: $0) }
        }
        let ranked = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.room.recencyRank < rhs.room.recencyRank
        }
        return ranked.prefix(limit).map(\.room)
    }

    /// The rows to show: the ranked rooms, then the people.
    ///
    /// - Parameters:
    ///   - rankedRooms: the output of `rankRooms`.
    ///   - query: the typed text. An exact user ID gets a person row even if
    ///     the directory did not return it (the New Chat rule, so a bridge
    ///     bot can be found).
    ///   - directoryResults: the user directory results for the query, in
    ///     server order. Empty until the debounced search returns.
    ///   - ownUserId: the signed-in user, never listed as a person.
    ///   - mode: picker mode lists rooms only.
    /// - Returns: rooms first, then people who match the query and do not
    ///   already show as the partner of a listed DM room, without
    ///   duplicates.
    public static func merge(
        rankedRooms: [QuickSwitcherRoom],
        query: String,
        directoryResults: [NewChatPerson],
        ownUserId: String?,
        mode: QuickSwitcherMode
    ) -> [QuickSwitcherResult] {
        let roomRows = rankedRooms.map(QuickSwitcherResult.room)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .navigate, !trimmed.isEmpty else { return roomRows }

        let listedDirectPartners = Set(rankedRooms.compactMap { $0.isDirect ? $0.directUserId : nil })
        let people = NewChatResults.assemble(
            query: trimmed,
            resolvedProfile: nil,
            searchResults: directoryResults,
            ownUserId: ownUserId,
            selectedUserIds: listedDirectPartners
        )
        // Results from an earlier query stay on screen until the debounced
        // search for this one returns. Drop the ones this query no longer
        // matches, so the list never shows an unrelated person.
        let matching = people.filter { person in
            QuickSwitcherFuzzy.score(query: trimmed, candidate: person.label) != nil
                || QuickSwitcherFuzzy.score(query: trimmed, candidate: person.userId) != nil
        }
        return roomRows + matching.map(QuickSwitcherResult.person)
    }

    /// Whether the user directory should be searched for `query`.
    public static func shouldSearchDirectory(query: String, mode: QuickSwitcherMode) -> Bool {
        mode == .navigate && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The step for an activated row.
    ///
    /// - Parameters:
    ///   - result: the activated row.
    ///   - mode: what the switcher is for.
    ///   - key: Return or ⌥-Return.
    /// - Returns: in picker mode, the picked room, whatever the key. In
    ///   navigate mode, open the room (⌥-Return: in a new window) or start
    ///   the DM with the person. ⌥-Return on a person is ignored until
    ///   MATRIX-116 defines it.
    public static func decide(
        _ result: QuickSwitcherResult,
        mode: QuickSwitcherMode,
        key: QuickSwitcherActivationKey
    ) -> QuickSwitcherDecision {
        switch (mode, result, key) {
        case let (.pickRoom, .room(room), _):
            .pickRoom(roomId: room.id)
        case (.pickRoom, .person, _):
            .ignore
        case let (.navigate, .room(room), .primary):
            .openRoom(roomId: room.id)
        case let (.navigate, .room(room), .alternate):
            .openRoomInNewWindow(roomId: room.id)
        case let (.navigate, .person(person), .primary):
            .startDirectChat(userId: person.userId)
        case (.navigate, .person, .alternate):
            .ignore
        }
    }
}
