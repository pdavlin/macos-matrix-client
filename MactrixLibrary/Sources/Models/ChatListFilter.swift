import Foundation

/// The sidebar chat-list filter (MATRIX-67).
///
/// Each case is one SDK room-list filter; the mapping to
/// `RoomListEntriesDynamicFilterKind` lives in the app target. MATRIX-206:
/// Archived is the app's own state (`InboxStateDocument`), not a room tag;
/// the SDK narrows the list to the archived rooms by identifier.
///
/// MATRIX-224: Unanswered and Drafts are app rules too. Drafts narrows the
/// SDK list to the rooms with a saved draft, like Archived. Unanswered keeps
/// the Inbox's SDK filter and drops the other chats app-side
/// (`ChatListUnanswered`), because the rule reads the latest event.
public enum ChatListFilter: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Every room that is not low priority.
    case inbox
    /// Inbox rooms with unread messages or the marked-unread flag.
    case unread
    /// Inbox chats whose last message is from another person and has no
    /// own reaction (MATRIX-224, `ChatListUnanswered`).
    case unanswered
    /// Inbox chats with a saved composer draft (MATRIX-224).
    case drafts
    /// Inbox rooms the SDK classifies as people (DMs).
    case people
    /// Inbox rooms the SDK classifies as groups.
    case groups
    /// Rooms tagged low priority.
    case lowPriority
    /// Archived chats (MATRIX-206). Every other filter leaves them out.
    case archived
    /// Snoozed chats (MATRIX-207). Every other filter leaves them out.
    case snoozed

    public var id: Self { self }

    /// The inbox placement this filter shows (MATRIX-206, MATRIX-207):
    /// Archived and Snoozed show their chats, every other filter the chats
    /// in the Inbox.
    public var inboxPlacement: InboxPlacement {
        switch self {
        case .inbox, .unread, .unanswered, .drafts, .people, .groups, .lowPriority: .inbox
        case .archived: .archived
        case .snoozed: .snoozed
        }
    }

    /// The SDK list holds only the rooms the app names
    /// (`.identifiers`): Archived, Snoozed, and Drafts. Without a narrowing
    /// such a filter shows no chat.
    public var narrowsByRoomIds: Bool {
        switch self {
        case .archived, .snoozed, .drafts: true
        case .inbox, .unread, .unanswered, .people, .groups, .lowPriority: false
        }
    }

    /// The rooms the SDK list is narrowed to for this filter: the rail
    /// filter's rooms, and for a filter that `narrowsByRoomIds` only its
    /// rooms among them. Sorted, so the value changes only when the set
    /// changes. Nil when nothing narrows the list.
    ///
    /// - Parameters:
    ///   - rail: the rail filter's rooms, or nil for the Inbox.
    ///   - placementRoomIds: the rooms that show in an inbox placement
    ///     (MATRIX-206, MATRIX-207). Read only for Archived and Snoozed.
    ///   - draftRoomIds: the rooms with a draft (MATRIX-224). Read only for
    ///     Drafts.
    public func narrowingRoomIds(
        rail: [String]?,
        placementRoomIds: (InboxPlacement) -> Set<String>,
        draftRoomIds: () -> Set<String>
    ) -> [String]? {
        let kept: Set<String>
        if self == .drafts {
            kept = draftRoomIds()
        } else if inboxPlacement != .inbox {
            kept = placementRoomIds(inboxPlacement)
        } else {
            return rail
        }
        guard let rail else { return kept.sorted() }
        return rail.filter(kept.contains).sorted()
    }

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .unread: "Unread"
        case .unanswered: "Unanswered"
        case .drafts: "Drafts"
        case .people: "People"
        case .groups: "Groups"
        case .lowPriority: "Low Priority"
        case .archived: "Archived"
        case .snoozed: "Snoozed"
        }
    }

    public var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .unread: "circlebadge"
        case .unanswered: "arrowshape.turn.up.left"
        case .drafts: "square.and.pencil"
        case .people: "person"
        case .groups: "person.3"
        case .lowPriority: "arrow.down.to.line"
        case .archived: "archivebox"
        case .snoozed: "moon.zzz"
        }
    }
}

// MARK: - iOS (MATRIX-247)

public extension ChatListFilter {
    /// The filters the iOS chat list offers in its toolbar menu. iOS has no
    /// rail, so it offers the views that together hold every chat: the
    /// Inbox and Low Priority, and (MATRIX-248) Archived and Snoozed, the
    /// chats the Mac's inbox state takes out of the other two.
    static let iosChoices: [ChatListFilter] = [.inbox, .lowPriority, .archived, .snoozed]

    /// The filter an iOS scene restores from its stored raw value: the
    /// stored filter if iOS offers it, else the Inbox.
    static func iosChoice(restoring rawValue: String?) -> ChatListFilter {
        guard let rawValue, let filter = ChatListFilter(rawValue: rawValue), iosChoices.contains(filter) else {
            return .inbox
        }
        return filter
    }

    /// The iOS chat list's title: "Chats" for the Inbox, else the filter's
    /// title.
    var iosListTitle: String {
        self == .inbox ? "Chats" : title
    }
}
