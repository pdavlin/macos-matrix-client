import Core
import Models
import SwiftUI
import UI

/// The detail area of a selected merged chat (MATRIX-141 Phase B): the
/// placeholder until the merged timeline lands (Wave 2 replaces this view).
///
/// It reads the merged chat from the live document, so a rename or a member
/// change shows at once. A merged chat the document does not hold (a restored
/// window before the first read of the merged chats) shows the empty state.
struct MergedChatDetailContainer: View {
    @Environment(AppState.self) private var appState

    let mergedChatId: String

    var body: some View {
        if let client = appState.matrixClient, let content = Self.content(mergedChatId: mergedChatId, client: client) {
            MergedChatDetailPlaceholder(mergedRow: content.mergedRow, members: content.members, imageLoader: client)
        } else {
            ContentUnavailableView("Select a room", systemImage: "message.fill")
        }
    }

    /// The merged row and the member rows, built with the chat list's rules
    /// (`ChatListMerging`), so the avatar, title, and badges match the
    /// sidebar row. Nil when the document does not hold the merged chat.
    private static func content(
        mergedChatId: String,
        client: MatrixClient
    ) -> (mergedRow: ChatListRowModel, members: [ChatListRowModel])? {
        guard let merge = client.mergedChats?.merge(id: mergedChatId) else { return nil }
        let members = merge.rooms.map { roomId in
            client.chatListRow(forRoomId: roomId) ?? ChatListRowModel(id: roomId, title: roomId, isDirect: true)
        }
        guard let merged = ChatListMerging.entry(for: merge, members: members.map { ChatListEntry(row: $0) }) else {
            return nil
        }
        return (merged.row, members)
    }
}
