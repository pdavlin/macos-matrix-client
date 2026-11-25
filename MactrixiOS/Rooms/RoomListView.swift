import Models
import SwiftUI
import UI

/// The room list: the iPhone stack root and the iPad sidebar. Rows are
/// `NavigationLink(value:)` with the room id. In a `NavigationStack` the link
/// pushes onto the path; in a `NavigationSplitView` sidebar it sets the
/// `selection` binding. Pass `nil` for a stack so the list is not selectable.
///
/// MATRIX-247: while the search field holds a query, the list shows the
/// search results in place of the sections. A result is a link with the room
/// id too, so a tap opens the room as a tap on a row does.
///
/// MATRIX-248: a merged chat is one row. Its link holds the room id of its
/// newest member, so a tap opens that room with the normal timeline.
struct RoomListView<Item: RoomListItem>: View {
    let chats: [RoomListChat<Item>]
    /// The search results, best first, or nil to show the sections.
    var searchResults: [QuickSwitcherRoom]?
    let isLoading: Bool
    let imageLoader: (any UI.ImageLoader)?
    let selection: Binding<String?>?
    /// The list's filter, for the empty state.
    var filter: ChatListFilter = .inbox
    /// Loads the next page of rooms. Called when the last row shows.
    var loadMore: (@MainActor () -> Void)?

    var body: some View {
        let sections = RoomListSections.make(chats: chats)

        Group {
            if let selection {
                List(selection: selection) {
                    content(sections)
                }
            } else {
                List {
                    content(sections)
                }
            }
        }
        .overlay {
            if let searchResults {
                if searchResults.isEmpty {
                    ContentUnavailableView.search
                        .accessibilityIdentifier("roomSearchEmpty")
                }
            } else if sections.isEmpty {
                RoomListEmptyState(isLoading: isLoading, filter: filter)
            }
        }
    }

    @ViewBuilder
    private func content(_ sections: [RoomListSection<Item>]) -> some View {
        if let searchResults {
            ForEach(searchResults) { room in
                NavigationLink(value: ChatListSearch.roomToOpen(room)) {
                    RoomSearchRow(room: room, imageLoader: imageLoader)
                }
            }
        } else {
            rows(sections)
        }
    }

    private func rows(_ sections: [RoomListSection<Item>]) -> some View {
        let lastRoomID = RoomListSections.lastRoomID(in: sections)
        return ForEach(sections) { section in
            Section(section.kind.title) {
                ForEach(section.chats) { chat in
                    NavigationLink(value: chat.roomToOpen) {
                        switch chat {
                        case let .room(room):
                            RoomListRow(room: room, imageLoader: imageLoader)
                        case let .merged(merged):
                            MergedChatListRow(row: merged.row, imageLoader: imageLoader)
                        }
                    }
                    .onAppear {
                        if chat.id == lastRoomID { loadMore?() }
                    }
                }
            }
        }
    }
}

/// One room: the shared `UI.RoomRow` (avatar, DM or room placeholder icon,
/// bold title and badge when unread) plus a muted indicator.
struct RoomListRow<Item: RoomListItem>: View {
    let room: Item
    let imageLoader: (any UI.ImageLoader)?

    var body: some View {
        UI.RoomRow(
            title: room.title,
            avatarUrl: room.avatarUrl,
            roomInfo: room.info,
            imageLoader: imageLoader,
            joinRoom: nil
        )
        .modifier(RoomRowMuteMark(isMuted: room.isMuted))
        .accessibilityIdentifier("roomRow")
    }
}

/// One merged chat (MATRIX-248), drawn as `UI.RoomRow` draws a room: the
/// merged chat's name and avatar (the avatar member's image, as the Mac
/// row picks it), bold with a badge when unread, and the muted indicator.
///
/// The unread state is the Mac merged row's (`ChatListMerging.unread`):
/// the counts of the members that are not muted add up, and the row is
/// muted when every member is. The badge is gray only when the row is
/// muted, as the Mac's count capsule.
struct MergedChatListRow: View {
    let row: ChatListRowModel
    let imageLoader: (any UI.ImageLoader)?

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 22

    var body: some View {
        Label {
            Text(row.title)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            UI.AvatarImage(avatarUrl: row.avatarUrl, imageLoader: imageLoader) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.clear)
                    .overlay {
                        Image(systemName: row.isDirect ? "person.fill" : "number")
                    }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .fontWeight(row.unread.isUnread ? .bold : .regular)
        .badge(Int(clamping: row.unread.count))
        .badgeProminence(row.unread.isMuted ? .standard : .increased)
        .listItemTint(.gray)
        .modifier(RoomRowMuteMark(isMuted: row.unread.isMuted))
        .accessibilityIdentifier("mergedChatRow")
    }
}

/// The muted indicator at the trailing edge of a list row.
private struct RoomRowMuteMark: ViewModifier {
    let isMuted: Bool

    @ScaledMetric(relativeTo: .body) private var muteIconWidth: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(.trailing, isMuted ? muteIconWidth : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                if isMuted {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                        .accessibilityLabel("Muted")
                }
            }
    }
}

/// One search result (MATRIX-247): the avatar and name as a list row draws
/// them, and the room's alias under the name when it has one.
///
/// MATRIX-248: a merged chat's result has the merged name and avatar. An
/// archived or snoozed chat shows its ⌘K mark ("Archived", "Snoozed until
/// …", the result's `detail`) in place of the alias, as ⌘K shows the detail
/// in place of the alias.
struct RoomSearchRow: View {
    let room: QuickSwitcherRoom
    let imageLoader: (any UI.ImageLoader)?

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 22

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .lineLimit(1)
                if let subtitle = room.detail ?? room.canonicalAlias {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } icon: {
            UI.AvatarImage(avatarUrl: room.avatarUrl, imageLoader: imageLoader) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.clear)
                    .overlay {
                        Image(systemName: room.isDirect ? "person.fill" : "number")
                    }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("roomSearchResult")
    }
}

/// The toolbar menu that picks the list filter (MATRIX-247): Inbox, Low
/// Priority, and (MATRIX-248) Archived and Snoozed. The icon fills while
/// the list shows a filter other than the Inbox.
struct RoomListFilterMenu: View {
    let filter: Binding<ChatListFilter>

    var body: some View {
        Menu {
            Picker("Show", selection: filter) {
                ForEach(ChatListFilter.iosChoices) { choice in
                    Label(choice.title, systemImage: choice.systemImage)
                        .tag(choice)
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: filter.wrappedValue == .inbox
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .accessibilityIdentifier("chatListFilterMenu")
    }
}

struct RoomListEmptyState: View {
    let isLoading: Bool
    var filter: ChatListFilter = .inbox

    var body: some View {
        if isLoading {
            ContentUnavailableView {
                ProgressView()
            } description: {
                Text("Loading rooms")
            }
            .accessibilityIdentifier("roomListLoading")
        } else {
            switch filter {
            case .lowPriority:
                empty("No Low Priority Chats", description: "Chats marked as low priority appear here.")
            case .archived:
                // MATRIX-248: the phone shows the Mac's inbox state; it
                // has no Archive action of its own.
                empty("No Archived Chats", description: "Chats you archive on your Mac appear here.")
            case .snoozed:
                empty("No Snoozed Chats", description: "Chats you snooze on your Mac appear here.")
            case .inbox, .unread, .unanswered, .drafts, .people, .groups:
                ContentUnavailableView(
                    "No Rooms",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Rooms and direct messages appear here.")
                )
                .accessibilityIdentifier("roomListEmpty")
            }
        }
    }

    private func empty(_ title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        ContentUnavailableView(title, systemImage: filter.systemImage, description: Text(description))
            .accessibilityIdentifier("roomListEmpty")
    }
}
