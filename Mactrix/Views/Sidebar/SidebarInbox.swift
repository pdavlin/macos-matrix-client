import Core
import MatrixRustSDK
import Models
import SwiftUI
import UI

// MATRIX-206: the app-side glue for Archive. The rules are in
// `Models/InboxState.swift`, the storage in `Core/InboxStateModel.swift`.

/// The inbox actions every entry point shares: the row menus, ⌘K, and the
/// File menu.
@MainActor
enum SidebarInbox {
    /// The chat's rooms: one room, or every member of the merged chat that
    /// holds it.
    static func roomIds(of selection: ChatSelection, client: MatrixClient?) -> [String] {
        switch selection {
        case let .room(roomId):
            return [roomId]
        case let .merged(mergedChatId):
            return client?.mergedChats?.merge(id: mergedChatId)?.rooms ?? []
        }
    }

    /// The name the note shows for a chat.
    static func name(of selection: ChatSelection, client: MatrixClient?) -> String {
        switch selection {
        case let .room(roomId):
            let room = client?.rooms.first { $0.id == roomId }?.room ?? (try? client?.client?.getRoom(roomId: roomId))
            return room?.displayName() ?? "chat"
        case let .merged(mergedChatId):
            return client?.mergedChats?.merge(id: mergedChatId)?.name ?? "chat"
        }
    }

    /// The list the chat shows in.
    static func placement(of roomIds: [String], client: MatrixClient?) -> InboxPlacement {
        guard let inbox = client?.inbox, let first = roomIds.first else { return .inbox }
        return inbox.placement(of: first)
    }

    /// Archives the chat and shows the note with Undo in the window.
    static func archive(roomIds: [String], name: String, client: MatrixClient?, windowState: WindowState) {
        guard let inbox = client?.inbox, inbox.isEditable, !roomIds.isEmpty else { return }
        let previous = inbox.states(of: roomIds)
        Task {
            await inbox.archive(roomIds: roomIds)
            windowState.inboxNotice = .archived(name, undoStates: previous)
        }
    }

    /// Moves the chat back to the Inbox.
    static func unarchive(roomIds: [String], client: MatrixClient?) {
        client?.inbox?.unarchive(roomIds: roomIds)
    }

    /// Archives an Inbox chat, or moves an archived chat back.
    static func toggleArchive(roomIds: [String], name: String, client: MatrixClient?, windowState: WindowState) {
        if placement(of: roomIds, client: client) == .archived {
            unarchive(roomIds: roomIds, client: client)
        } else {
            archive(roomIds: roomIds, name: name, client: client, windowState: windowState)
        }
    }

    /// The SDK narrowing for the window: the rail filter's rooms, and for
    /// the Archived list filter only the archived rooms among them. Sorted,
    /// so the value changes only when the set changes.
    static func narrowingRoomIds(client: MatrixClient?, windowState: WindowState) -> [String]? {
        let rail = SidebarRail.narrowingRoomIds(client: client, windowState: windowState)
        let placement = windowState.chatListFilter.inboxPlacement
        guard placement != .inbox else { return rail }
        let kept = client?.inbox?.roomIds(in: placement) ?? []
        guard let rail else { return kept.sorted() }
        return rail.filter(kept.contains).sorted()
    }
}

/// The Archive and Unarchive items of a chat's context menu.
struct ArchiveMenuItems: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let roomIds: [String]
    let name: String

    var body: some View {
        let client = appState.matrixClient
        let isEditable = client?.inbox?.isEditable ?? false
        if SidebarInbox.placement(of: roomIds, client: client) == .archived {
            Button {
                SidebarInbox.unarchive(roomIds: roomIds, client: client)
            } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
            .disabled(!isEditable)
        } else {
            Button {
                SidebarInbox.archive(roomIds: roomIds, name: name, client: client, windowState: windowState)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .disabled(!isEditable)
        }
    }
}

/// The note with Undo at the foot of the chat list. It goes away after
/// `InboxNotice.duration`, or when a new note replaces it.
struct InboxNoticeOverlay: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    var body: some View {
        if let notice = windowState.inboxNotice {
            InboxNoticeToast(message: notice.message) {
                appState.matrixClient?.inbox?.restore(notice.undoStates)
                windowState.inboxNotice = nil
            }
            .padding(10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: notice.id) {
                try? await Task.sleep(for: InboxNotice.duration)
                guard !Task.isCancelled, windowState.inboxNotice?.id == notice.id else { return }
                windowState.inboxNotice = nil
            }
        }
    }
}

/// The key window's Archive command, for the File menu (⌘E).
struct InboxCommand: Equatable {
    /// The selected chat is archived: the item reads "Unarchive Chat".
    let isArchived: Bool
    /// Archives or unarchives the selected chat.
    let toggle: @MainActor () -> Void

    /// The menu rebuilds only when the title changes.
    static func == (lhs: InboxCommand, rhs: InboxCommand) -> Bool {
        lhs.isArchived == rhs.isArchived
    }
}

extension FocusedValues {
    /// The key window's Archive command, published by
    /// `InboxCommandPublisher`. Nil when no chat is selected or the inbox
    /// states cannot be written.
    @Entry var inboxCommand: InboxCommand?
}

/// Publishes the window's `InboxCommand` for the File menu.
struct InboxCommandPublisher: ViewModifier {
    @Environment(AppState.self) private var appState
    let windowState: WindowState

    func body(content: Content) -> some View {
        content.focusedSceneValue(\.inboxCommand, command)
    }

    private var command: InboxCommand? {
        let client = appState.matrixClient
        guard !windowState.isSingleRoomWindow,
              let selection = windowState.chatSelection,
              client?.inbox?.isEditable == true
        else { return nil }
        let roomIds = SidebarInbox.roomIds(of: selection, client: client)
        guard !roomIds.isEmpty else { return nil }
        let isArchived = SidebarInbox.placement(of: roomIds, client: client) == .archived
        return InboxCommand(isArchived: isArchived) { [windowState] in
            let name = SidebarInbox.name(of: selection, client: client)
            SidebarInbox.toggleArchive(roomIds: roomIds, name: name, client: client, windowState: windowState)
        }
    }
}
