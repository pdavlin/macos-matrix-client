import Core
import Models
import OSLog
import SwiftUI

/// The context menu of a chat-list row or pinned tile (MATRIX-141): the room
/// menu for a plain room, the merged-chat menu for a merged row.
struct ChatListItemContextMenu: View {
    let item: ChatListItem
    let chats: SidebarChatList

    var body: some View {
        switch item {
        case .room:
            if let room = chats.rooms(of: item).first {
                RoomContextMenu(room: room)
            }
        case let .merged(merged):
            MergedChatContextMenu(merged: merged)
        }
    }
}

/// The context menu of a merged row (MATRIX-141).
///
/// Edit and Unmerge write the merged-chats document. Mark as Read and
/// Mute/Unmute are the normal per-room calls, made for every member room
/// (contract §11, 2026-11-10: presentation only; mute decision 2026-11-10:
/// muting the merged chat mutes every member).
struct MergedChatContextMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let merged: MergedChatListEntry

    var body: some View {
        let mergedChats = appState.matrixClient?.mergedChats
        let isEditable = mergedChats?.isEditable ?? false
        let isMuted = merged.row.unread.isMuted
        // Every member, not only the ones the filter shows: the action is
        // for the merged chat.
        let memberRoomIds = merged.merge.rooms

        Button {
            windowState.mergeEditor = .edit(mergedChatId: merged.id)
        } label: {
            Label("Edit Merged Chat…", systemImage: "pencil")
        }
        .disabled(!isEditable)

        // No confirmation: merging again undoes it.
        Button {
            Task {
                let outcome = await mergedChats?.unmerge(merged.id)
                if outcome != .saved {
                    Logger.viewCycle.error("unmerge from the chat list did not land: \(String(describing: outcome), privacy: .public)")
                }
            }
        } label: {
            Label("Unmerge", systemImage: "rectangle.stack.badge.minus")
        }
        .disabled(!isEditable)

        Divider()

        Button {
            Task { await appState.matrixClient?.markAsRead(roomIds: memberRoomIds) }
        } label: {
            Text("Mark as Read")
        }
        .disabled(!merged.row.unread.isUnread)

        Button {
            Task { await appState.matrixClient?.setMuted(!isMuted, roomIds: memberRoomIds) }
        } label: {
            if isMuted {
                Label("Unmute", systemImage: "bell")
            } else {
                Label("Mute", systemImage: "bell.slash")
            }
        }
    }
}
