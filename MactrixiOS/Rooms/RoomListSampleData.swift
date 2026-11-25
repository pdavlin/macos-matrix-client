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

        /// The item as the shared chat list reads it (MATRIX-248), with the
        /// time of its latest message.
        func chatListEntry(lastActivity: Date? = nil) -> ChatListEntry {
            ChatListEntry(
                row: ChatListRowModel(
                    id: id,
                    title: title,
                    avatarUrl: avatarUrl,
                    isDirect: isDirect,
                    unread: ChatListUnread(
                        numUnreadMessages: unreadMessages,
                        numUnreadNotifications: unreadNotifications,
                        numUnreadMentions: unreadMentions,
                        isMarkedUnread: false,
                        isMuted: isMuted
                    )
                ),
                lastActivity: lastActivity,
                isFavourite: isFavourite
            )
        }

        /// MATRIX-248: one person on two networks, merged on the Mac as
        /// "Seth". The WhatsApp chat has the newer message.
        static let sethMembers: [SampleRoomListItem] = [
            .init(id: "!seth-wa", title: "Seth (WhatsApp)", isDirect: true, unreadMessages: 2, unreadNotifications: 2),
            .init(id: "!seth-signal", title: "Seth (Signal)", isDirect: true, unreadMessages: 1, unreadNotifications: 1),
        ]

        static let sethMerge = MergedChatDocument(merges: [
            MergedChat(id: "merged-seth", name: "Seth", rooms: ["!seth-signal", "!seth-wa"]),
        ])

        /// The list's rows as the app builds them (MATRIX-248): the shared
        /// rule (`ChatListMerging.visible`, as `MatrixClient.visibleChatList`
        /// calls it, with no rail and no labels) over `items`. Each item's
        /// latest message is one minute older than the one before it, so
        /// the order is the SDK's recency order.
        static func chats(
            _ items: [SampleRoomListItem],
            merges: MergedChatDocument = sethMerge,
            inbox: InboxStateDocument = InboxStateDocument(),
            filter: ChatListFilter = .inbox
        ) -> [RoomListChat<SampleRoomListItem>] {
            let newest = Date(timeIntervalSince1970: 1_800_000_000)
            let entries = items.filter { !$0.isSpace }.enumerated().map { index, item in
                item.chatListEntry(lastActivity: newest.addingTimeInterval(-60 * Double(index)))
            }
            let visible = ChatListMerging.visible(
                entries: entries,
                filter: .inbox,
                labels: ChatLabelDocument(),
                spaces: RoomSpaceMap(),
                document: merges,
                inbox: inbox,
                placement: filter.inboxPlacement
            )
            return RoomListChats.make(from: visible.ordered, rooms: items)
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
        RoomNavigationShell(rooms: SampleRoomListItem.all, isLoading: false, imageLoader: nil, usesStack: true) { _ in
            TimelineFixtureConversation(feed: TimelineFixtureFeed())
        }
    }

    #Preview("Merged chat") {
        let rooms = SampleRoomListItem.sethMembers + SampleRoomListItem.all
        RoomNavigationShell(
            rooms: rooms,
            chats: SampleRoomListItem.chats(rooms),
            isLoading: false,
            imageLoader: nil,
            usesStack: true
        ) { _ in
            TimelineFixtureConversation(feed: TimelineFixtureFeed())
        }
    }

    #Preview("iPad split") {
        RoomNavigationShell(rooms: SampleRoomListItem.all, isLoading: false, imageLoader: nil, usesStack: false) { _ in
            TimelineFixtureConversation(feed: TimelineFixtureFeed())
        }
    }

    #Preview("Loading") {
        RoomNavigationShell(rooms: [SampleRoomListItem](), isLoading: true, imageLoader: nil, usesStack: true) { _ in
            TimelineFixtureConversation(feed: TimelineFixtureFeed())
        }
    }
#endif
