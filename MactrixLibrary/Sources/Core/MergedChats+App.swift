import Foundation
import MatrixRustSDK
import Models
import OSLog

// MATRIX-141 Phase B: the app's merged-chat actions.
//
// Presentation only (contract §11, 2026-11-10): the merged chats live in the
// account-data document, and every room action below is the normal per-room
// SDK call, made once for each member room.

/// How a write of the merged chats ended, for the Merge Chats sheet.
public enum MergedChatWriteOutcome: Equatable, Sendable {
    /// The document now holds the change.
    case saved
    /// The stored document is unreadable or from a newer version of the app,
    /// so this build does not write it (`MergedChatsModel.isEditable`).
    case notEditable
    /// The write did not land: the SDK call failed. The model logged why.
    case failed
}

public extension MergedChatsModel {
    /// Writes the Merge Chats sheet's draft as the merged chat `id` and waits
    /// for the write.
    ///
    /// - Parameters:
    ///   - draft: the sheet's draft.
    ///   - id: a new UUID string for a new merged chat, the existing ID when
    ///     editing.
    /// - Returns: `.saved` when the document holds the draft afterwards.
    func save(_ draft: MergedChatDraft, as id: String) async -> MergedChatWriteOutcome {
        guard isEditable else { return .notEditable }
        await mutate { $0.apply(draft, to: id) }.value
        if document.holds(draft, as: id) {
            return .saved
        }
        return isEditable ? .failed : .notEditable
    }

    /// Removes the merged chat `id` and waits for the write. Its rooms show
    /// as normal chats again.
    ///
    /// - Returns: `.saved` when the document no longer holds the merged chat.
    func unmerge(_ id: String) async -> MergedChatWriteOutcome {
        guard isEditable else { return .notEditable }
        await mutate { $0.unmerge(id) }.value
        if document.merge(id: id) == nil {
            return .saved
        }
        return isEditable ? .failed : .notEditable
    }

    /// Takes a room the user left through the app out of its merged chat
    /// (orchestrator decision 2026-11-11: no automatic prune of left rooms).
    /// A merged chat left with one room is removed. Does nothing for a room
    /// in no merged chat.
    ///
    /// - Parameter roomId: the room the user left.
    func removeLeftRoom(_ roomId: String) {
        guard merge(containing: roomId) != nil else { return }
        mutate { document in
            guard let merge = document.merge(containing: roomId) else { return }
            document.removeRoom(roomId, from: merge.id)
        }
    }
}

public extension SidebarRoom {
    /// The room as the merged-chat pass of the chat list reads it
    /// (`ChatListMerging`).
    ///
    /// - Parameters:
    ///   - now: decides the timestamp bucket of the row.
    ///   - mutedByLabel: every label that holds the room is muted (MATRIX-77).
    func chatListEntry(now: Date = .now, mutedByLabel: Bool = false) -> ChatListEntry {
        ChatListEntry(
            row: chatListRow(now: now, mutedByLabel: mutedByLabel),
            lastActivity: latestEvent?.timestamp,
            isFavourite: roomInfo?.isFavourite == true,
            isMarkedUnread: roomInfo?.isMarkedUnread == true
        )
    }
}

public extension MatrixClient {
    /// The chat-list row of a room, for the Merge Chats sheet and the merged
    /// chat's detail area.
    ///
    /// The sidebar's rooms hold only what the window's filter allows, so a
    /// room outside the filter gets a row from the SDK's room store: its
    /// name and avatar, without the network badge or unread state.
    ///
    /// - Parameter roomId: the room.
    /// - Returns: nil when the client does not know the room.
    func chatListRow(forRoomId roomId: String) -> ChatListRowModel? {
        if let sidebarRoom = rooms.first(where: { $0.id == roomId }) {
            var row = sidebarRoom.chatListRow()
            row.account = roomAccounts.account(of: roomId, network: row.network)
            return row
        }
        guard let room = try? client.getRoom(roomId: roomId) else { return nil }
        return ChatListRowModel(
            id: roomId,
            title: room.displayName() ?? roomId,
            avatarUrl: room.avatarUrl(),
            isDirect: true
        )
    }

    /// What tells each member chat of a merged chat apart, by room ID
    /// (`MergedMemberIdentity.detail`, "Slack • DevObsessed"), for the Merge
    /// Chats sheet and the merged chat's inspector.
    ///
    /// The sidebar's room knows its heroes; a room outside the window's
    /// filter has only its row. A chat with nothing known gets no entry.
    ///
    /// - Parameter rows: the member chats' rows (`chatListRow(forRoomId:)`).
    func mergedMemberDetails(for rows: [ChatListRowModel]) -> [String: String] {
        var details: [String: String] = [:]
        for row in rows {
            let identity = rooms.first { $0.id == row.id }?.mergedMemberIdentity(accounts: roomAccounts)
                ?? MergedMemberIdentity(row: row, parentNames: roomAccounts.names[row.id] ?? [])
            details[row.id] = identity.detail
        }
        return details
    }

    /// Mutes or unmutes rooms through the SDK's per-room notification mode
    /// (MATRIX-141). A merged chat is muted when every member is
    /// (orchestrator decision 2026-11-10), so the merged row's Mute and
    /// Unmute apply this to every member.
    ///
    /// Mute sets the mode to `.mute`. Unmute uses the SDK's `unmuteRoom`,
    /// which goes back to the default mode, and to all messages only when
    /// that default is mute. Rooms the client does not know are skipped. A
    /// failure is logged and the other rooms still change.
    ///
    /// - Parameters:
    ///   - muted: true to mute.
    ///   - roomIds: the rooms.
    func setMuted(_ muted: Bool, roomIds: [String]) async {
        let settings = await client.getNotificationSettings()
        for roomId in roomIds {
            do {
                guard let room = try client.getRoom(roomId: roomId) else { continue }
                if muted {
                    try await settings.setRoomNotificationMode(roomId: roomId, mode: .mute)
                } else {
                    let info = try await room.roomInfo()
                    try await settings.unmuteRoom(
                        roomId: roomId,
                        isEncrypted: room.isEncrypted(),
                        isOneToOne: info.activeMembersCount == 2
                    )
                }
            } catch {
                let reason = String(describing: error)
                Logger.mergedChats.error(
                    "failed to set muted=\(muted, privacy: .public) on \(roomId, privacy: .public): \(reason, privacy: .public)"
                )
            }
        }
    }

    /// Marks rooms as read (MATRIX-141, a merged row's "Mark as Read"): a
    /// read receipt on each room's latest event, then the marked-unread flag
    /// cleared where it is set. Rooms the client does not know are skipped. A
    /// failure is logged and the other rooms still change.
    ///
    /// - Parameter roomIds: the rooms.
    func markAsRead(roomIds: [String]) async {
        for roomId in roomIds {
            do {
                guard let room = try client.getRoom(roomId: roomId) else { continue }
                try await room.markAsRead(receiptType: .read)
                if try await room.roomInfo().isMarkedUnread {
                    try await room.setUnreadFlag(newValue: false)
                }
            } catch {
                Logger.mergedChats.error(
                    "failed to mark \(roomId, privacy: .public) as read: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}
