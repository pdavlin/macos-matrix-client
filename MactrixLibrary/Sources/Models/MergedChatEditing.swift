import Foundation

// MATRIX-141 Phase B: which chats can be merged, and how the Merge Chats
// sheet writes its draft.
//
// v1 limit (contract §11, 2026-11-10): only one-to-one chats merge. A chat is
// one-to-one when the SDK marks it direct (`RoomInfo.isDirect`), the same flag
// the chat list reads (`ChatListRowModel.isDirect`). A bridged DM often has a
// bridge bot as a third member, so the member count is not used.

/// Where a room stands with merged chats, for the room inspector and the
/// chat-list context menu (MATRIX-141).
public enum RoomMergeStatus: Equatable, Sendable {
    /// The room cannot be merged: it is not a one-to-one chat.
    case unavailable
    /// A one-to-one chat in no merged chat: "Merge with…" starts one.
    case mergeable
    /// The room is a member of this merged chat.
    case member(of: MergedChat)

    /// Decides the status of a room.
    ///
    /// - Parameters:
    ///   - roomId: the room.
    ///   - isDirect: the room is a one-to-one chat.
    ///   - document: the account's merged chats.
    /// - Returns: `.member` for any member room (direct or not, because a
    ///   member must always be reachable to unmerge it), `.mergeable` for a
    ///   one-to-one chat in no merged chat, else `.unavailable`.
    public static func of(roomId: String, isDirect: Bool, document: MergedChatDocument) -> RoomMergeStatus {
        if let merge = document.merge(containing: roomId) {
            return .member(of: merge)
        }
        return isDirect ? .mergeable : .unavailable
    }
}

/// The open Merge Chats sheet (MATRIX-141). `WindowState.mergeEditor` holds
/// it; the window that holds it shows the sheet.
public enum MergedChatEditorRequest: Hashable, Identifiable, Sendable {
    /// A new merged chat that starts with this one-to-one chat.
    case create(roomId: String)
    /// Edit this merged chat.
    case edit(mergedChatId: String)

    public var id: String {
        switch self {
        case let .create(roomId): "create:\(roomId)"
        case let .edit(mergedChatId): "edit:\(mergedChatId)"
        }
    }
}

/// The chats the "Add Chat…" picker of the Merge Chats sheet offers
/// (MATRIX-141).
public enum MergedChatPicking {
    /// Whether the picker offers a chat.
    ///
    /// A chat is offered when it is a one-to-one chat, it is not in the draft
    /// yet, and it is in no merged chat other than the one being edited. A
    /// chat in another merged chat is left out, not moved: moving a chat
    /// between merged chats is done by unmerging first, so a pick never
    /// changes a merged chat the user does not see.
    ///
    /// - Parameters:
    ///   - roomId: the candidate chat.
    ///   - isDirect: the candidate is a one-to-one chat.
    ///   - draft: the sheet's draft.
    ///   - editingId: the merged chat the sheet edits, or nil for a new one.
    ///   - document: the account's merged chats.
    public static func offers(
        roomId: String,
        isDirect: Bool,
        draft: MergedChatDraft,
        editingId: String?,
        document: MergedChatDocument
    ) -> Bool {
        guard isDirect, !draft.rooms.contains(roomId) else { return false }
        guard let owner = document.merge(containing: roomId) else { return true }
        return owner.id == editingId
    }
}

public extension MergedChatDocument {
    /// Writes the Merge Chats sheet's draft as the merged chat `id`: creates
    /// it when the document has no merged chat with this ID, else replaces
    /// its members, name, default room, and avatar room.
    ///
    /// A merged chat that another device removed while the sheet was open is
    /// created again with the same ID, because Save states what the user
    /// wants to see.
    ///
    /// - Parameters:
    ///   - draft: the sheet's draft. `draft.canSubmit` should hold.
    ///   - id: a new UUID string for a new merged chat, the existing ID when
    ///     editing.
    /// - Returns: false when the draft was refused (fewer than two chats);
    ///   the document is then unchanged.
    @discardableResult
    mutating func apply(_ draft: MergedChatDraft, to id: String) -> Bool {
        let wanted = draft.mergedChat(id: id)
        guard merge(id: id) != nil else {
            return create(
                name: wanted.name,
                rooms: wanted.rooms,
                defaultRoom: wanted.defaultRoom,
                avatarRoom: wanted.avatarRoom,
                id: id
            ) != nil
        }
        guard setRooms(wanted.rooms, for: id) else { return false }
        rename(id, to: wanted.name)
        setDefaultRoom(wanted.defaultRoom, for: id)
        setAvatarRoom(wanted.avatarRoom, for: id)
        return true
    }

    /// Whether the merged chat `id` is exactly what `draft` asks for: the
    /// check that a save landed.
    func holds(_ draft: MergedChatDraft, as id: String) -> Bool {
        merge(id: id) == draft.mergedChat(id: id)
    }
}
