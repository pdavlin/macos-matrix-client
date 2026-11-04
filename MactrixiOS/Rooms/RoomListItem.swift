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

/// A titled group of rooms. The order inside a section is the SDK room list
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
    let rooms: [Item]

    var id: Kind { kind }
}

/// The Mac sidebar's grouping rules: favorites first, then DMs, then rooms.
/// Spaces stay out of the iOS list (the E-APP-05 fence covers M1 only).
/// Empty sections are left out.
enum RoomListSections {
    @MainActor
    static func make<Item: RoomListItem>(from items: [Item]) -> [RoomListSection<Item>] {
        let visible = items.filter { !$0.isSpace }
        let favorites = visible.filter(\.isFavourite)
        let directs = visible.filter { $0.isDirect && !$0.isFavourite }
        let rooms = visible.filter { !$0.isDirect && !$0.isFavourite }

        return [
            RoomListSection(kind: .favorites, rooms: favorites),
            RoomListSection(kind: .directs, rooms: directs),
            RoomListSection(kind: .rooms, rooms: rooms),
        ]
        .filter { !$0.rooms.isEmpty }
    }
}
