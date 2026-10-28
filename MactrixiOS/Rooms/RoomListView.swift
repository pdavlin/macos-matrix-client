import SwiftUI
import UI

/// The room list: the iPhone stack root and the iPad sidebar. Rows are
/// `NavigationLink(value:)` with the room id. In a `NavigationStack` the link
/// pushes onto the path; in a `NavigationSplitView` sidebar it sets the
/// `selection` binding. Pass `nil` for a stack so the list is not selectable.
struct RoomListView<Item: RoomListItem>: View {
    let rooms: [Item]
    let isLoading: Bool
    let imageLoader: (any UI.ImageLoader)?
    let selection: Binding<String?>?

    var body: some View {
        let sections = RoomListSections.make(from: rooms)

        Group {
            if let selection {
                List(selection: selection) {
                    rows(sections)
                }
            } else {
                List {
                    rows(sections)
                }
            }
        }
        .overlay {
            if sections.isEmpty {
                RoomListEmptyState(isLoading: isLoading)
            }
        }
    }

    private func rows(_ sections: [RoomListSection<Item>]) -> some View {
        ForEach(sections) { section in
            Section(section.kind.title) {
                ForEach(section.rooms) { room in
                    NavigationLink(value: room.id) {
                        RoomListRow(room: room, imageLoader: imageLoader)
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

struct RoomListEmptyState: View {
    let isLoading: Bool

    var body: some View {
        if isLoading {
            ContentUnavailableView {
                ProgressView()
            } description: {
                Text("Loading rooms")
            }
            .accessibilityIdentifier("roomListLoading")
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
