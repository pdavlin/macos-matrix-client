import Core
import MatrixRustSDK
import Models

/// One row of the iOS room list. `SidebarRoom` is the live conformance; the
/// protocol keeps the section rules and the views testable without SDK rooms.
@MainActor
protocol RoomListItem: Identifiable where ID == String {
    /// The SDK-computed name. mautrix bridges set portal names and avatars as
    /// room state, so a bridged chat shows the remote contact here.
    var title: String { get }
    var avatarUrl: String? { get }
    var info: (any Models.RoomInfo)? { get }
    var isFavourite: Bool { get }
    var isDirect: Bool { get }
    var isSpace: Bool { get }
    var isMuted: Bool { get }
}

extension SidebarRoom: RoomListItem {
    var title: String {
        room.displayName() ?? (isDirect ? "Unknown user" : "Unknown room")
    }

    var avatarUrl: String? {
        room.avatarUrl()
    }

    var info: (any Models.RoomInfo)? {
        roomInfo
    }

    var isFavourite: Bool {
        roomInfo?.isFavourite == true
    }

    var isDirect: Bool {
        roomInfo?.isDirect == true
    }

    var isSpace: Bool {
        room.isSpace()
    }

    var isMuted: Bool {
        RoomMuteState.isMuted(roomInfo?.cachedUserDefinedNotificationMode)
    }
}

/// Maps the room's user-defined notification mode to the muted indicator.
/// Only an explicit `.mute` counts: mentions-only rooms still notify.
enum RoomMuteState {
    static func isMuted(_ mode: RoomNotificationMode?) -> Bool {
        mode == .mute
    }
}

/// One row of the iOS chat list (MATRIX-248): a room, or a merged chat.
///
/// The rows come from the shared chat list rule
/// (`MatrixClient.visibleChatList`, `ChatListMerging.visible`), so the
/// member rooms of a merged chat are one row, as on the Mac. iOS has no
/// merged timeline: a merged row opens its newest member room.
enum RoomListChat<Item: RoomListItem>: Identifiable {
    case room(Item)
    case merged(MergedChatListEntry)

    /// The room ID, or the merged chat's ID.
    var id: String {
        switch self {
        case let .room(room): room.id
        case let .merged(merged): merged.id
        }
    }

    /// The room a tap opens: the room itself, or the merged chat's newest
    /// member (`MergedChatListEntry.newestRoomId`: the present member with
    /// the newest message, `ChatListMerging`).
    var roomToOpen: String {
        switch self {
        case let .room(room): room.id
        case let .merged(merged): merged.newestRoomId
        }
    }

    /// A merged chat is a favourite when any present member is one.
    @MainActor var isFavourite: Bool {
        switch self {
        case let .room(room): room.isFavourite
        case let .merged(merged): merged.isFavourite
        }
    }

    /// A merged chat is direct when the member it takes its avatar from is.
    @MainActor var isDirect: Bool {
        switch self {
        case let .room(room): room.isDirect
        case let .merged(merged): merged.row.isDirect
        }
    }

    @MainActor var isSpace: Bool {
        switch self {
        case let .room(room): room.isSpace
        case .merged: false
        }
    }
}

/// The iOS chat list's rows from the shared chat list (MATRIX-248).
enum RoomListChats {
    /// Each item of the shared list as a row: a plain room as its list
    /// item, a merged chat as itself, in the items' order. A room that
    /// `rooms` does not hold is left out.
    ///
    /// - Parameters:
    ///   - items: the shared list, favourites first
    ///     (`VisibleChatList.ordered`).
    ///   - rooms: the list items the shared list came from.
    @MainActor
    static func make<Item: RoomListItem>(from items: [ChatListItem], rooms: [Item]) -> [RoomListChat<Item>] {
        let roomsByID = Dictionary(rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return items.compactMap { item -> RoomListChat<Item>? in
            switch item {
            case let .room(entry):
                return roomsByID[entry.id].map { RoomListChat<Item>.room($0) }
            case let .merged(merged):
                return RoomListChat<Item>.merged(merged)
            }
        }
    }
}

/// A titled group of chats. The order inside a section is the SDK room list
/// order, which the room list service sorts by recency.
struct RoomListSection<Item: RoomListItem>: Identifiable {
    enum Kind: String, CaseIterable {
        case favorites
        case directs
        case rooms

        var title: String {
            switch self {
            case .favorites: "Favorites"
            case .directs: "Direct Messages"
            case .rooms: "Rooms"
            }
        }
    }

    let kind: Kind
    let chats: [RoomListChat<Item>]

    var id: Kind { kind }
}

/// The Mac sidebar's grouping rules: favorites first, then DMs, then rooms.
/// Spaces stay out of the iOS list (the E-APP-05 fence covers M1 only).
/// Empty sections are left out.
enum RoomListSections {
    /// The sections of plain rooms, with no merged chats.
    @MainActor
    static func make<Item: RoomListItem>(from items: [Item]) -> [RoomListSection<Item>] {
        make(chats: items.map { RoomListChat<Item>.room($0) })
    }

    /// MATRIX-248: the sections of the list's rows. A merged chat is a
    /// favourite when any present member is one, and direct when its
    /// avatar member is.
    @MainActor
    static func make<Item: RoomListItem>(chats: [RoomListChat<Item>]) -> [RoomListSection<Item>] {
        let visible = chats.filter { !$0.isSpace }
        let favorites = visible.filter(\.isFavourite)
        let directs = visible.filter { $0.isDirect && !$0.isFavourite }
        let rooms = visible.filter { !$0.isDirect && !$0.isFavourite }

        return [
            RoomListSection(kind: .favorites, chats: favorites),
            RoomListSection(kind: .directs, chats: directs),
            RoomListSection(kind: .rooms, chats: rooms),
        ]
        .filter { !$0.chats.isEmpty }
    }

    /// The chat on the list's last row (MATRIX-247): a room ID, or a merged
    /// chat's ID. When it shows, the user has seen every loaded room, and
    /// the list loads the next page. Each section keeps the SDK order, so a
    /// new page adds rooms to the sections and moves this row down.
    @MainActor
    static func lastRoomID(in sections: [RoomListSection<some RoomListItem>]) -> String? {
        sections.last?.chats.last?.id
    }
}
