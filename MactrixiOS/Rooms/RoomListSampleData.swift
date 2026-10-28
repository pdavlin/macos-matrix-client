#if DEBUG
    import Models
    import SwiftUI

    /// Static rooms for previews. No SDK objects, no account.
    struct SampleRoomListItem: RoomListItem {
        let id: String
        let title: String
        let avatarUrl: String? = nil
        let isFavourite: Bool
        let isDirect: Bool
        let isSpace: Bool
        let isMuted: Bool
        let unreadMessages: UInt64
        let unreadNotifications: UInt64
        let unreadMentions: UInt64

        init(
            id: String,
            title: String,
            isFavourite: Bool = false,
            isDirect: Bool = false,
            isSpace: Bool = false,
            isMuted: Bool = false,
            unreadMessages: UInt64 = 0,
            unreadNotifications: UInt64 = 0,
            unreadMentions: UInt64 = 0
        ) {
            self.id = id
            self.title = title
            self.isFavourite = isFavourite
            self.isDirect = isDirect
            self.isSpace = isSpace
            self.isMuted = isMuted
            self.unreadMessages = unreadMessages
            self.unreadNotifications = unreadNotifications
            self.unreadMentions = unreadMentions
        }

        var info: (any Models.RoomInfo)? {
            SampleRoomInfo(item: self)
        }

        static let all: [SampleRoomListItem] = [
            .init(id: "!fav", title: "Family", isFavourite: true, unreadMessages: 3, unreadNotifications: 3),
            .init(id: "!dm1", title: "Alex (Signal)", isDirect: true, unreadMessages: 2, unreadNotifications: 2),
            .init(id: "!dm2", title: "Sam (WhatsApp)", isDirect: true),
            .init(id: "!room1", title: "#eng-platform (Slack)", unreadMessages: 12, unreadMentions: 1),
            .init(id: "!room2", title: "Neighborhood", isMuted: true, unreadMessages: 40),
            .init(id: "!space", title: "Work space", isSpace: true),
        ]
    }

    /// A `Models.RoomInfo` built from a sample row, for `UI.RoomRow`.
    struct SampleRoomInfo: Models.RoomInfo {
        let item: SampleRoomListItem

        var id: String { item.id }
        var creators: [String]? { nil }
        var displayName: String? { item.title }
        var rawName: String? { item.title }
        var topic: String? { nil }
        var avatarUrl: String? { nil }
        var isDirect: Bool { item.isDirect }
        var isPublic: Bool? { false }
        var isSpace: Bool { item.isSpace }
        var isFavourite: Bool { item.isFavourite }
        var canonicalAlias: String? { nil }
        var alternativeAliases: [String] { [] }
        var activeMembersCount: UInt64 { 2 }
        var invitedMembersCount: UInt64 { 0 }
        var joinedMembersCount: UInt64 { 2 }
        var highlightCount: UInt64 { item.unreadMentions }
        var notificationCount: UInt64 { item.unreadNotifications }
        var hasRoomCall: Bool { false }
        var activeRoomCallParticipants: [String] { [] }
        var isMarkedUnread: Bool { false }
        var numUnreadMessages: UInt64 { item.unreadMessages }
        var numUnreadNotifications: UInt64 { item.unreadNotifications }
        var numUnreadMentions: UInt64 { item.unreadMentions }
        var pinnedEventIds: [String] { [] }
        var roomVersion: String? { "12" }
        var privilegedCreatorsRole: Bool { false }
    }

    #Preview("iPhone list") {
        RoomNavigationShell(rooms: SampleRoomListItem.all, isLoading: false, imageLoader: nil, usesStack: true)
    }

    #Preview("iPad split") {
        RoomNavigationShell(rooms: SampleRoomListItem.all, isLoading: false, imageLoader: nil, usesStack: false)
    }

    #Preview("Loading") {
        RoomNavigationShell(rooms: [SampleRoomListItem](), isLoading: true, imageLoader: nil, usesStack: true)
    }
#endif
