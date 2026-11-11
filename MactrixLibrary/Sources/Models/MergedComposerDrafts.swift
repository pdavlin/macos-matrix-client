import Foundation

/// The drafts of the merged chats' composers (MATRIX-143 Phase B).
///
/// **Decision.** A merged chat's composer keeps one draft per merged chat,
/// in memory, for the app session. It never reads or writes the SDK draft of
/// a member room: the target room can change while the user writes, so an
/// SDK draft could end up in a room the message does not go to. Each member
/// room keeps its own SDK draft, and the single-room composer still loads
/// and saves it as before.
///
/// The draft is the composer text only (mention chips as `matrix.to` pill
/// links, as in `MentionMarkdown`). A reply or an edit is not kept: both
/// name an event of one member room, and they end when the user leaves the
/// merged chat. While the composer edits a message, the draft is the text
/// from before the edit, which comes back when the edit ends.
///
/// Usage:
/// ```swift
/// var drafts = MergedComposerDrafts()
/// drafts.save(composerText: "Hi Seth", textBeforeEdit: nil, forMerge: merge.id)
/// drafts.text(forMerge: merge.id) // "Hi Seth"
/// ```
public struct MergedComposerDrafts: Equatable, Sendable {
    private var texts: [String: String] = [:]

    public init() {}

    /// The draft text of a merged chat, or "" when there is none.
    public func text(forMerge mergeId: String) -> String {
        texts[mergeId] ?? ""
    }

    /// Saves the draft of a merged chat for the composer's current state.
    ///
    /// - Parameters:
    ///   - composerText: The text in the composer.
    ///   - textBeforeEdit: While the composer edits a message, the text from
    ///     before the edit; nil when it does not edit.
    ///   - mergeId: The merged chat's ID (`MergedChat.id`).
    public mutating func save(composerText: String, textBeforeEdit: String?, forMerge mergeId: String) {
        let text = Self.textToKeep(composerText: composerText, textBeforeEdit: textBeforeEdit)
        texts[mergeId] = text.isEmpty ? nil : text
    }

    /// Drops every draft, for example when the account signs out.
    public mutating func removeAll() {
        texts.removeAll()
    }

    /// The text a draft keeps: the text from before an edit while the
    /// composer edits, else the composer text. An edit is never kept as the
    /// draft, so a later new message does not start with the edited text.
    public static func textToKeep(composerText: String, textBeforeEdit: String?) -> String {
        textBeforeEdit ?? composerText
    }
}

public extension MergedComposerTargeting {
    /// The member room of the newest message the composer can edit, for the
    /// Up arrow in an empty merged composer.
    ///
    /// Each member room offers its newest own editable message; the newest
    /// of those wins. A tie goes to the room that comes first in member
    /// order, as in the send-target rule.
    ///
    /// - Parameters:
    ///   - candidates: The time of each member room's newest editable
    ///     message, by room ID. A room with no such message is missing.
    ///   - rooms: The merge's member room IDs, in member order.
    /// - Returns: The room, or nil when no member room has a candidate.
    static func newestEditRoom(candidates: [String: Date], rooms: [String]) -> String? {
        var newest: (roomId: String, date: Date)?
        for roomId in rooms {
            guard let date = candidates[roomId] else { continue }
            if let current = newest, date <= current.date { continue }
            newest = (roomId, date)
        }
        return newest?.roomId
    }
}

/// The window title and subtitle of a merged chat (MATRIX-142 Phase B).
public enum MergedChatHeader {
    /// The subtitle under the merged chat's name: the label of each member
    /// room in member order, as the source notes show it, and how many
    /// member rooms did not load.
    ///
    /// For example "Slack • DevObsessed and Slack • pizza box audit
    /// committee", or with a failed room "Slack • DevObsessed (1 chat did
    /// not load)".
    ///
    /// - Parameters:
    ///   - labels: The source labels of the member rooms that loaded, in
    ///     member order.
    ///   - failedCount: How many member rooms did not load
    ///     (`MergedLiveTimeline.failedRoomIds`).
    public static func subtitle(labels: [MergedSourceLabel], failedCount: Int) -> String {
        let names = labels.map(\.headerText)
        let list = ListFormatter.localizedString(byJoining: names)
        guard failedCount > 0 else { return list }
        let failure = failedCount == 1
            ? String(localized: "1 chat did not load", comment: "Merged chat subtitle: one member chat failed to load.")
            : String(
                localized: "\(failedCount) chats did not load",
                comment: "Merged chat subtitle: how many member chats failed to load."
            )
        guard !list.isEmpty else { return failure }
        return String(
            localized: "\(list) (\(failure))",
            comment: "Merged chat subtitle: the member chats, then the load failure in parentheses."
        )
    }
}

extension MergedSourceLabel {
    /// "Slack • DevObsessed", or the title alone.
    var headerText: String {
        guard let detail else { return title }
        return String(
            localized: "\(title) • \(detail)",
            comment: "A merged chat member: a network name, then the chat that tells two rooms of that network apart."
        )
    }
}
