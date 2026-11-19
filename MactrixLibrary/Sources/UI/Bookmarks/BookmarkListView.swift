import Models
import SwiftUI
import Tokens

/// The Bookmarks list (MATRIX-208): every bookmarked message across rooms,
/// the newest saved first. Go > Bookmarks (⇧⌘B) shows it as a sheet.
///
/// Each row shows the room's avatar and name, the sender, a one-line
/// preview, and the message time. A click opens the message. A message that
/// does not load reads "Message not available" and offers Remove. Every
/// row's right-click menu has Remove Bookmark.
public struct BookmarkListView: View {
    static let avatarSize: CGFloat = 32

    let rows: [BookmarkListRow]
    let imageLoader: ImageLoader?
    let timeText: (Date) -> String
    let open: @MainActor (BookmarkKey) -> Void
    let remove: @MainActor (BookmarkKey) -> Void

    @State private var hoveredId: BookmarkKey?
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - rows: from `BookmarkListRow.rows(for:rooms:messages:)`.
    ///   - imageLoader: loads the room avatars.
    ///   - timeText: the message time as the row shows it. The chat list's
    ///     wording by default; snapshot tests pass fixed text.
    ///   - open: opens the bookmarked message. The sheet closes first.
    ///   - remove: removes the bookmark.
    public init(
        rows: [BookmarkListRow],
        imageLoader: ImageLoader?,
        timeText: @escaping (Date) -> String = { ChatListTimestamp.text(for: $0) },
        open: @escaping @MainActor (BookmarkKey) -> Void,
        remove: @escaping @MainActor (BookmarkKey) -> Void
    ) {
        self.rows = rows
        self.imageLoader = imageLoader
        self.timeText = timeText
        self.open = open
        self.remove = remove
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Right-click a message and choose Bookmark.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            rowView(row)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 520, height: 440)
    }

    private var header: some View {
        HStack {
            Text("Bookmarks")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// A row that can open is one button. An unavailable row is not a
    /// button, so its Remove button gets the click.
    @ViewBuilder
    private func rowView(_ row: BookmarkListRow) -> some View {
        Group {
            if row.content == .unavailable {
                styledContent(row)
            } else {
                Button {
                    dismiss()
                    open(row.id)
                } label: {
                    styledContent(row)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .onHover { inside in
            if inside {
                hoveredId = row.id
            } else if hoveredId == row.id {
                hoveredId = nil
            }
        }
        .contextMenu {
            Button("Remove Bookmark", systemImage: "bookmark.slash") {
                remove(row.id)
            }
        }
    }

    private func styledContent(_ row: BookmarkListRow) -> some View {
        BookmarkRowContent(row: row, imageLoader: imageLoader, timeText: timeText) {
            remove(row.id)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(hoveredId == row.id && row.content != .unavailable ? 0.12 : 0))
        )
        .contentShape(Rectangle())
    }
}

/// One row's content: the avatar, the room and the time, then the sender
/// and the preview, or "Message not available" with Remove.
struct BookmarkRowContent: View {
    let row: BookmarkListRow
    let imageLoader: ImageLoader?
    let timeText: (Date) -> String
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarImage(avatarUrl: row.room.avatarUrl, imageLoader: imageLoader) {
                ChatListAvatarPlaceholder(initials: row.room.initials, size: BookmarkListView.avatarSize)
            }
            .frame(width: BookmarkListView.avatarSize, height: BookmarkListView.avatarSize)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.room.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if case let .message(message) = row.content {
                        Text(timeText(message.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                detail
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch row.content {
        case .loading:
            Text("Loading…")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        case let .message(message):
            Text("\(Text(message.senderName).fontWeight(.medium))\(message.preview.isEmpty ? "" : ": \(message.preview)")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        case .unavailable:
            HStack {
                Text("Message not available")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove", action: remove)
                    .controlSize(.small)
            }
        }
    }
}
