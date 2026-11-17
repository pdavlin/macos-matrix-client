import Foundation

/// One chat a broadcast sends to (MATRIX-168; contract §11, 2026-11-16).
///
/// A broadcast sends one text message to each chat of the rail filter
/// (MATRIX-172: every chat the account has, see `BroadcastTargetList`).
/// A plain chat is one target. A merged chat is one target too: the message
/// goes to one member room, not to every member.
public struct BroadcastTarget: Identifiable, Equatable, Sendable {
    /// The sidebar row's ID: the room ID, or the merged chat's ID.
    public var id: String
    /// The row the sheet draws: the title and the avatar inputs.
    public var row: ChatListRowModel
    /// The room the message goes to.
    public var roomId: String
    /// The merged chat's ID, or nil for a plain chat.
    public var mergedChatId: String?

    public init(id: String, row: ChatListRowModel, roomId: String, mergedChatId: String? = nil) {
        self.id = id
        self.row = row
        self.roomId = roomId
        self.mergedChatId = mergedChatId
    }

    /// The chat's name, as the sidebar shows it.
    public var title: String {
        row.title
    }

    /// The targets of a rail filter: one per sidebar row, in sidebar order
    /// (the pinned grid, then the list).
    ///
    /// - The Inbox gives no target: a broadcast needs a label or a space.
    /// - A space is never a target. `items` holds chats only.
    /// - A merged chat gives one target. Its room comes from the merged
    ///   chat's send-target rule (`MergedSendTarget.resolve`) over the
    ///   members the filter shows, so a broadcast to a label never sends to
    ///   a member room outside that label. The sidebar does not know who
    ///   wrote last in each member room, so with the default (empty)
    ///   `activity` the rule gives the merged chat's default room when the
    ///   filter shows it, else the first member the filter shows.
    ///
    /// - Parameters:
    ///   - items: the rows the sidebar shows for `filter`
    ///     (`ChatListMerging.visible(entries:filter:labels:spaces:document:)`,
    ///     `ordered`).
    ///   - filter: the resolved rail filter.
    ///   - activity: the newest message times per member room ID, if known.
    ///   - now: the current time, for the send-target rule.
    public static func targets(
        items: [ChatListItem],
        filter: ChatListRailFilter,
        activity: [String: MergedSendTarget.RoomActivity] = [:],
        now: Date = .now
    ) -> [BroadcastTarget] {
        guard filter != .inbox else { return [] }
        var seen = Set<String>()
        return items.compactMap { item -> BroadcastTarget? in
            guard seen.insert(item.id).inserted else { return nil }
            switch item {
            case let .room(entry):
                return BroadcastTarget(id: entry.id, row: entry.row, roomId: entry.id)
            case let .merged(merged):
                guard let target = MergedSendTarget.resolve(
                    rooms: merged.memberRoomIds,
                    defaultRoom: merged.merge.effectiveDefaultRoom,
                    activity: activity,
                    manualPick: nil,
                    now: now
                ) else { return nil }
                return BroadcastTarget(id: merged.id, row: merged.row, roomId: target.roomId, mergedChatId: merged.id)
            }
        }
    }

    /// The targets of a rail filter, from the client's chat rooms. The
    /// parameters are those of
    /// `ChatListMerging.visible(entries:filter:labels:spaces:document:)`.
    public static func targets(
        entries: [ChatListEntry],
        filter: ChatListRailFilter,
        labels: ChatLabelDocument,
        spaces: RoomSpaceMap,
        document: MergedChatDocument,
        now: Date = .now
    ) -> [BroadcastTarget] {
        // A label the labels do not hold shows the Inbox.
        if case let .label(id) = filter, labels.label(id: id) == nil {
            return []
        }
        let visible = ChatListMerging.visible(
            entries: entries, filter: filter, labels: labels, spaces: spaces, document: document
        )
        return targets(items: visible.ordered, filter: filter, now: now)
    }
}

/// What the broadcast sheet edits: the text and the checked targets. Not
/// stored anywhere (contract §11, 2026-11-16, decision 5).
public struct BroadcastDraft: Equatable, Sendable {
    public var text: String
    /// The IDs of the checked targets.
    public var selectedIds: Set<String>

    public init(text: String = "", selectedIds: Set<String> = []) {
        self.text = text
        self.selectedIds = selectedIds
    }

    /// A new draft: no text, every target checked.
    public init(targets: [BroadcastTarget]) {
        self.init(text: "", selectedIds: Set(targets.map(\.id)))
    }

    /// The text that goes out: the draft text without the white space and
    /// the empty lines at its ends.
    public var outgoingText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The checked targets, in the order of `targets`.
    public func selectedTargets(in targets: [BroadcastTarget]) -> [BroadcastTarget] {
        targets.filter { selectedIds.contains($0.id) }
    }

    /// Whether the review step can open: the text is not blank and at least
    /// one of `targets` is checked.
    public func canReview(targets: [BroadcastTarget]) -> Bool {
        !outgoingText.isEmpty && targets.contains { selectedIds.contains($0.id) }
    }

    public mutating func setSelected(_ isSelected: Bool, id: String) {
        if isSelected {
            selectedIds.insert(id)
        } else {
            selectedIds.remove(id)
        }
    }

    public mutating func selectAll(_ targets: [BroadcastTarget]) {
        selectedIds = Set(targets.map(\.id))
    }

    public mutating func selectNone() {
        selectedIds = []
    }
}

/// The confirm rule of the review step (contract §11, 2026-11-16,
/// decision 4).
public enum BroadcastConfirmation {
    /// Above this number of targets, the user must type the count.
    public static let typedCountThreshold = 20

    /// Whether the review step shows the count field.
    public static func needsTypedCount(targetCount: Int) -> Bool {
        targetCount > typedCountThreshold
    }

    /// Whether the "Send to N Chats" button is enabled.
    ///
    /// - Parameters:
    ///   - targetCount: the number of checked targets.
    ///   - typedCount: the content of the count field.
    public static func isConfirmed(targetCount: Int, typedCount: String) -> Bool {
        guard targetCount > 0 else { return false }
        guard needsTypedCount(targetCount: targetCount) else { return true }
        return Int(typedCount.trimmingCharacters(in: .whitespaces)) == targetCount
    }
}

/// Reads a broadcast text for custom emoji tokens.
public enum BroadcastText {
    /// Whether the text can hold a `:name:` custom emoji token: two colons
    /// with one or more characters and no white space between them. A cheap
    /// test that decides if a target room's image packs must load before
    /// the send. `ComposerEmojiMarkup` decides what resolves.
    public static func mayHoldEmojiToken(_ text: String) -> Bool {
        var runLength: Int?
        for character in text {
            if character == ":" {
                if let length = runLength, length > 0 {
                    return true
                }
                runLength = 0
            } else if character.isWhitespace {
                runLength = nil
            } else if let length = runLength {
                runLength = length + 1
            }
        }
        return false
    }
}
