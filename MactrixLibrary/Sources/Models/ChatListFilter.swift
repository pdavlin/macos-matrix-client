import Foundation

/// The sidebar chat-list filter (MATRIX-67).
///
/// Each case is one SDK room-list filter; the mapping to
/// `RoomListEntriesDynamicFilterKind` lives in the app target. MATRIX-206:
/// Archived is the app's own state (`InboxStateDocument`), not a room tag;
/// the SDK narrows the list to the archived rooms by identifier.
public enum ChatListFilter: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Every room that is not low priority.
    case inbox
    /// Inbox rooms with unread messages or the marked-unread flag.
    case unread
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
        case .inbox, .unread, .people, .groups, .lowPriority: .inbox
        case .archived: .archived
        case .snoozed: .snoozed
        }
    }

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .unread: "Unread"
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
        case .people: "person"
        case .groups: "person.3"
        case .lowPriority: "arrow.down.to.line"
        case .archived: "archivebox"
        case .snoozed: "moon.zzz"
        }
    }
}
