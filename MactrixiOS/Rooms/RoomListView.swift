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
struct RoomListView<Item: RoomListItem>: View {
    let rooms: [Item]
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
        let sections = RoomListSections.make(from: rooms)

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
                ForEach(section.rooms) { room in
                    NavigationLink(value: room.id) {
                        RoomListRow(room: room, imageLoader: imageLoader)
                    }
                    .onAppear {
                        if room.id == lastRoomID { loadMore?() }
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

    @ScaledMetric(relativeTo: .body) private var muteIconWidth: CGFloat = 22

    var body: some View {
        UI.RoomRow(
            title: room.title,
            avatarUrl: room.avatarUrl,
            roomInfo: room.info,
            imageLoader: imageLoader,
            joinRoom: nil
        )
        .padding(.trailing, room.isMuted ? muteIconWidth : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if room.isMuted {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                    .accessibilityLabel("Muted")
            }
        }
        .accessibilityIdentifier("roomRow")
    }
}

/// One search result (MATRIX-247): the avatar and name as a list row draws
/// them, and the room's alias under the name when it has one.
struct RoomSearchRow: View {
    let room: QuickSwitcherRoom
    let imageLoader: (any UI.ImageLoader)?

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 22

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .lineLimit(1)
                if let alias = room.canonicalAlias {
                    Text(alias)
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

/// The toolbar menu that picks the list filter (MATRIX-247): Inbox or Low
/// Priority. The icon fills while the list shows a filter other than the
/// Inbox.
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
        } else if filter == .lowPriority {
            ContentUnavailableView(
                "No Low Priority Chats",
                systemImage: ChatListFilter.lowPriority.systemImage,
                description: Text("Chats marked as low priority appear here.")
            )
            .accessibilityIdentifier("roomListEmpty")
        } else {
            ContentUnavailableView(
                "No Rooms",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Rooms and direct messages appear here.")
            )
            .accessibilityIdentifier("roomListEmpty")
        }
    }
}
