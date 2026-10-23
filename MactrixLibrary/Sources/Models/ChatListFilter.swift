import Foundation

/// The sidebar chat-list filter (MATRIX-67).
///
/// Each case is one SDK room-list filter; the mapping to
/// `RoomListEntriesDynamicFilterKind` lives in the app target. Beeper's
/// separate Archive bucket maps to Low Priority: the room tag is the only
/// archive-like state the SDK exposes.
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

    public var id: Self { self }

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .unread: "Unread"
        case .people: "People"
        case .groups: "Groups"
        case .lowPriority: "Low Priority"
        }
    }

    public var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .unread: "circlebadge"
        case .people: "person"
        case .groups: "person.3"
        case .lowPriority: "arrow.down.to.line"
        }
    }
}
