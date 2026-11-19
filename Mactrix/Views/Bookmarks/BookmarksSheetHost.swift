import Core
import Models
import SwiftUI
import UI

/// Wires `UI.BookmarkListView` to the signed-in client (MATRIX-208).
///
/// The rows come from the account's bookmarks. Each room and each message
/// is read through the SDK while the sheet shows (`MatrixClient
/// .bookmarkRoom(roomId:)`, `.bookmarkMessage(_:)`); nothing of a message is
/// stored. A click opens the message through the MATRIX-203 link path, so
/// a merged chat, a thread reply, and the flash on arrival work as they do
/// for a Matrix link in a message.
struct BookmarksSheetHost: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    /// The finished message reads, by key. A nil value is a read that
    /// failed.
    @State private var messages: [BookmarkKey: BookmarkListRow.Message?] = [:]

    var body: some View {
        if let client = appState.matrixClient, let bookmarks = client.bookmarks {
            let document = bookmarks.document
            BookmarkListView(
                rows: BookmarkListRow.rows(for: document, rooms: rooms(client: client, document: document), messages: messages),
                imageLoader: client,
                open: { key in open(key, client: client) },
                remove: { key in bookmarks.setBookmarked(false, roomId: key.roomId, eventId: key.eventId) }
            )
            .task(id: bookmarks.keys) {
                await loadMessages(document, client: client)
            }
        } else {
            ContentUnavailableView("Not signed in", systemImage: "person.crop.circle.badge.exclamationmark")
                .frame(width: 520, height: 440)
        }
    }

    /// The rooms of the bookmarks. One SDK room lookup per distinct room,
    /// none of them a request.
    private func rooms(client: MatrixClient, document: BookmarkDocument) -> [String: BookmarkListRow.Room] {
        var rooms: [String: BookmarkListRow.Room] = [:]
        for roomId in Set(document.bookmarks.map(\.roomId)) {
            rooms[roomId] = client.bookmarkRoom(roomId: roomId)
        }
        return rooms
    }

    /// Reads each message the sheet has not read yet, in list order.
    private func loadMessages(_ document: BookmarkDocument, client: MatrixClient) async {
        for bookmark in document.newestFirst where !messages.keys.contains(bookmark.key) {
            let message = await client.bookmarkMessage(bookmark.key)
            guard !Task.isCancelled else { return }
            messages[bookmark.key] = .some(message)
        }
    }

    private func open(_ key: BookmarkKey, client: MatrixClient) {
        let windowState = windowState
        Task {
            let (link, url) = await client.bookmarkLink(key)
            await client.openMatrixLink(link, url: url, in: windowState)
        }
    }
}
