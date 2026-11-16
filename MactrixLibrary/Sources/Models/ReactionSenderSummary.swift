import Foundation

/// Who posted one reaction, as the chip's tooltip and its accessibility
/// label say it (MATRIX-166).
///
/// Rules:
/// - The user IDs keep the reaction's order. A user ID that occurs twice
///   counts once, at its first place.
/// - The account's own user is "You".
/// - A user with no known display name shows the localpart of the user ID:
///   "ana" for "@ana:example.org".
/// - Up to `maxPeopleNamedInFull` (4) people are all named: "Ana",
///   "Ana and Ben", "Ana, Ben and You", "Ana, Ben, Cy and Di".
/// - More people show the first `namesShownWithOthers` (3) names and a
///   count: "Ana, Ben, Cy and 4 others". The count is then 2 or more.
/// - If the own user would be in the count, "You" takes the last named
///   place: "Ana, Ben, You and 4 others".
///
/// Usage:
/// ```swift
/// let summary = ReactionSenderSummary(
///     senderIds: reaction.senders.map(\.senderId),
///     ownUserId: ownUserId,
///     displayName: { names[$0] }
/// )
/// summary.tooltip(emojiName: "partyparrot") // ":partyparrot: · Ana and Ben"
/// ```
public struct ReactionSenderSummary: Equatable, Sendable {
    /// The most people the text names with no count.
    public static let maxPeopleNamedInFull = 4
    /// How many names the text shows before "and N others".
    public static let namesShownWithOthers = 3

    /// The names the text shows, in order.
    public let names: [String]
    /// How many people the text counts and does not name.
    public let otherCount: Int

    /// How many different people posted the reaction.
    public var peopleCount: Int {
        names.count + otherCount
    }

    /// - Parameters:
    ///   - senderIds: The senders' user IDs in the reaction's order.
    ///   - ownUserId: The account's own user ID.
    ///   - displayName: The display name of a user ID, or nil when it is not
    ///     known. It is called only for the users the text names.
    public init(senderIds: [String], ownUserId: String, displayName: (String) -> String?) {
        var seen = Set<String>()
        let people = senderIds.filter { seen.insert($0).inserted }

        var shown = people
        if people.count > Self.maxPeopleNamedInFull {
            shown = Array(people.prefix(Self.namesShownWithOthers))
            if !shown.contains(ownUserId), people.contains(ownUserId) {
                shown[shown.count - 1] = ownUserId
            }
        }

        names = shown.map { userId in
            if userId == ownUserId {
                return String(localized: "You", comment: "Reaction tooltip: the account's own user in the list of people.")
            }
            if let name = displayName(userId)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            return Self.localpart(of: userId)
        }
        otherCount = people.count - shown.count
    }

    /// The people: "Ana, Ben and You", or "Ana, Ben, You and 4 others".
    /// Empty when the reaction has no sender.
    public var peopleText: String {
        var parts = names
        if otherCount == 1 {
            parts.append(String(localized: "1 other", comment: "Reaction tooltip: one more person after the names."))
        } else if otherCount > 1 {
            parts.append(String(localized: "\(otherCount) others", comment: "Reaction tooltip: how many more people after the names."))
        }
        guard let last = parts.popLast() else { return "" }
        guard !parts.isEmpty else { return last }
        let head = parts.joined(separator: String(localized: ", ", comment: "Reaction tooltip: between two names in the list of people."))
        return String(localized: "\(head) and \(last)", comment: "Reaction tooltip: the list of people, then the last entry.")
    }

    /// The tooltip of the chip.
    ///
    /// - Parameter emojiName: The shortcode of a custom emoji, without its
    ///   colons, when the caller knows it. Nil or empty gives the people
    ///   only.
    /// - Returns: ":partyparrot: · Ana and Ben", or "Ana and Ben".
    public func tooltip(emojiName: String? = nil) -> String {
        guard let emojiName, !emojiName.isEmpty else { return peopleText }
        guard !names.isEmpty else { return ":\(emojiName):" }
        return String(
            localized: ":\(emojiName): · \(peopleText)",
            comment: "Reaction tooltip: the custom emoji's name, then the people who posted it."
        )
    }

    /// The accessibility label of the chip.
    ///
    /// - Parameter keyName: How to say the reaction key: the emoji itself
    ///   (the system reads "👍" as "thumbs up"), or a custom emoji's name.
    /// - Returns: "👍, 3 reactions: Ana, Ben and You".
    public func accessibilityLabel(keyName: String) -> String {
        guard peopleCount > 0 else { return keyName }
        if peopleCount == 1 {
            return String(
                localized: "\(keyName), 1 reaction: \(peopleText)",
                comment: "Reaction chip accessibility label: the emoji, then the one person who posted it."
            )
        }
        return String(
            localized: "\(keyName), \(peopleCount) reactions: \(peopleText)",
            comment: "Reaction chip accessibility label: the emoji, the number of people, then the people."
        )
    }

    /// "ana" for "@ana:example.org". A string that is not a user ID comes
    /// back without a leading "@".
    static func localpart(of userId: String) -> String {
        var rest = Substring(userId)
        if rest.hasPrefix("@") {
            rest = rest.dropFirst()
        }
        if let colon = rest.firstIndex(of: ":") {
            rest = rest[..<colon]
        }
        return rest.isEmpty ? userId : String(rest)
    }
}
