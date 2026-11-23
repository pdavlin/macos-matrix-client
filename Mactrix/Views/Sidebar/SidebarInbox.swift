import Core
import MatrixRustSDK
import Models
import SwiftUI
import UI

// MATRIX-206, MATRIX-207: the app-side glue for Archive, Snooze, and Remind
// Me Later. The rules are in `Models/InboxState.swift` and
// `Models/InboxState+Snooze.swift`, the storage and the timer in
// `Core/InboxStateModel.swift` and `Core/InboxStateModel+Due.swift`.

/// The inbox actions every entry point shares: the row menus, ⌘K, the File
/// menu, and the row's hover button (MATRIX-222).
///
/// MATRIX-222: Archive and Snooze on the open chat, and Mark as Read in its
/// row menu, open the next chat of the list (`openNextChat`), as Beeper does.
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

    /// Archives the chat and shows the note with Undo in the window. On
    /// the open chat, the next chat opens (MATRIX-222).
    static func archive(roomIds: [String], name: String, client: MatrixClient?, windowState: WindowState) {
        guard let inbox = client?.inbox, inbox.isEditable, !roomIds.isEmpty else { return }
        let previous = inbox.states(of: roomIds)
        openNextChat(ifOpenChatIn: roomIds, client: client, windowState: windowState)
        Task {
            await inbox.archive(roomIds: roomIds)
            windowState.inboxNotice = .archived(name, undoStates: previous)
        }
    }

    /// Moves the chat back to the Inbox.
    static func unarchive(roomIds: [String], client: MatrixClient?) {
        client?.inbox?.unarchive(roomIds: roomIds)
    }

    /// Snoozes the chat until `until` and shows the note with Undo. On the
    /// open chat, the next chat opens (MATRIX-222).
    static func snooze(roomIds: [String], until: Date, name: String, client: MatrixClient?, windowState: WindowState) {
        guard let inbox = client?.inbox, inbox.isEditable, !roomIds.isEmpty else { return }
        let previous = inbox.states(of: roomIds)
        openNextChat(ifOpenChatIn: roomIds, client: client, windowState: windowState)
        Task {
            await inbox.snooze(roomIds: roomIds, until: until)
            windowState.inboxNotice = .snoozed(name, until: InboxTimeText.when(until, now: .now), undoStates: previous)
        }
    }

    /// Sets a reminder on the chat and shows the note with Undo.
    static func remind(roomIds: [String], at remindAt: Date, name: String, client: MatrixClient?, windowState: WindowState) {
        guard let inbox = client?.inbox, inbox.isEditable, !roomIds.isEmpty else { return }
        let previous = inbox.states(of: roomIds)
        Task {
            await inbox.remind(roomIds: roomIds, at: remindAt)
            windowState.inboxNotice = .reminderSet(name, at: InboxTimeText.when(remindAt, now: .now), undoStates: previous)
        }
    }

    /// Runs an item of the chat's inbox menu.
    static func perform(_ action: InboxMenuAction, roomIds: [String], name: String, client: MatrixClient?, windowState: WindowState) {
        switch action {
        case .archive:
            archive(roomIds: roomIds, name: name, client: client, windowState: windowState)
        case .unarchive:
            unarchive(roomIds: roomIds, client: client)
        case let .snooze(until):
            snooze(roomIds: roomIds, until: until, name: name, client: client, windowState: windowState)
        case .unsnooze:
            client?.inbox?.unsnooze(roomIds: roomIds)
        case let .remind(at):
            remind(roomIds: roomIds, at: at, name: name, client: client, windowState: windowState)
        case .cancelReminder:
            client?.inbox?.cancelReminder(roomIds: roomIds)
        case let .pickDate(kind):
            windowState.inboxDatePicker = InboxDatePickerRequest(kind: kind, roomIds: roomIds, chatName: name)
        }
    }

    /// Archives an Inbox chat, or moves an archived chat back.
    static func toggleArchive(roomIds: [String], name: String, client: MatrixClient?, windowState: WindowState) {
        if placement(of: roomIds, client: client) == .archived {
            unarchive(roomIds: roomIds, client: client)
        } else {
            archive(roomIds: roomIds, name: name, client: client, windowState: windowState)
        }
    }

    /// Opens the next chat of the visible list when the window's open chat
    /// is among `roomIds` (MATRIX-222): the row below, at the end of the
    /// list the row above, with no other row nothing
    /// (`ChatListInboxFlow.nextChat(after:in:)`). The focus goes to the
    /// composer, as a click on the row does (MATRIX-188).
    ///
    /// Call it before the action changes the chat, while its row is still
    /// in the list. It does nothing when Settings turns it off, in a
    /// single-room window, or when the open chat is not in the list.
    ///
    /// - Parameter roomIds: the rooms the action is for. A member of a
    ///   merged chat counts for the merged chat.
    static func openNextChat(ifOpenChatIn roomIds: [String], client: MatrixClient?, windowState: WindowState) {
        guard InboxFlowPreferences.isOn(in: .standard),
              !windowState.isSingleRoomWindow,
              let open = windowState.chatSelection,
              !Set(self.roomIds(of: open, client: client)).isDisjoint(with: roomIds)
        else { return }
        let items = SidebarView.visibleChatList(client: client, windowState: windowState).visible.ordered
        switch ChatListInboxFlow.nextChat(after: open, in: items) {
        case .keep:
            return
        case let .open(selection):
            windowState.open(selection, from: .inboxFlow)
        case .clear:
            windowState.open(nil, from: .inboxFlow)
        }
    }

    /// The button a chat-list row shows under the pointer (MATRIX-222):
    /// Archive, or Unarchive in the Archived filter. A merged chat archives
    /// as one chat, as its menu does (MATRIX-206). Nil when the inbox
    /// states cannot be written.
    static func rowAction(for item: ChatListItem, client: MatrixClient?, windowState: WindowState) -> ChatListRowAction? {
        guard client?.inbox?.isEditable == true else { return nil }
        let selection = item.selection
        if windowState.chatListFilter.inboxPlacement == .archived {
            return ChatListRowAction(title: "Unarchive", systemImage: "tray.and.arrow.up") {
                unarchive(roomIds: roomIds(of: selection, client: client), client: client)
            }
        }
        return ChatListRowAction(title: "Archive", systemImage: "archivebox") {
            archive(
                roomIds: roomIds(of: selection, client: client),
                name: name(of: selection, client: client),
                client: client,
                windowState: windowState
            )
        }
    }

    // MARK: Archive All Read (MATRIX-222)

    /// "Archive All Read" can run: the list shows Inbox chats (not the
    /// Archived or Snoozed filter) and the inbox states can be written.
    static func canArchiveAllRead(client: MatrixClient?, windowState: WindowState) -> Bool {
        windowState.chatListFilter.inboxPlacement == .inbox && client?.inbox?.isEditable == true
    }

    /// Counts the read chats of the visible list and asks for the
    /// confirmation.
    static func requestArchiveAllRead(client: MatrixClient?, windowState: WindowState) {
        guard canArchiveAllRead(client: client, windowState: windowState) else { return }
        let visible = SidebarView.visibleChatList(client: client, windowState: windowState).visible
        let targets = ChatListInboxFlow.archiveAllReadTargets(in: visible)
        windowState.archiveAllRead = ArchiveAllReadRequest(itemIds: targets.map(\.id))
    }

    /// Archives the confirmed chats in one write and shows the note with
    /// Undo. A chat that turned unread or left the list after the
    /// confirmation showed stays. The open chat stays open.
    static func archiveAllRead(_ request: ArchiveAllReadRequest, client: MatrixClient?, windowState: WindowState) {
        guard let inbox = client?.inbox, inbox.isEditable else { return }
        let requested = Set(request.itemIds)
        let visible = SidebarView.visibleChatList(client: client, windowState: windowState).visible
        let targets = ChatListInboxFlow.archiveAllReadTargets(in: visible).filter { requested.contains($0.id) }
        let roomIds = targets.flatMap { self.roomIds(of: $0.selection, client: client) }
        guard !roomIds.isEmpty else { return }
        let previous = inbox.states(of: roomIds)
        Task {
            await inbox.archive(roomIds: roomIds)
            windowState.inboxNotice = .archivedAll(count: targets.count, undoStates: previous)
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

/// The inbox items of a chat's context menu: Archive, Snooze, and Remind
/// Me Later.
struct InboxMenuItems: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let roomIds: [String]
    let name: String

    var body: some View {
        let client = appState.matrixClient
        InboxMenuContent(
            placement: SidebarInbox.placement(of: roomIds, client: client),
            remindAt: roomIds.first.flatMap { client?.inbox?.remindAt(of: $0) },
            isEditable: client?.inbox?.isEditable ?? false
        ) { action in
            SidebarInbox.perform(action, roomIds: roomIds, name: name, client: client, windowState: windowState)
        }
    }
}

/// "Archive All Read…" in the chat list's menu (MATRIX-222). Beeper has
/// the same command.
struct ArchiveAllReadButton: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    var body: some View {
        Button {
            SidebarInbox.requestArchiveAllRead(client: appState.matrixClient, windowState: windowState)
        } label: {
            Label("Archive All Read…", systemImage: "archivebox")
        }
        .disabled(!SidebarInbox.canArchiveAllRead(client: appState.matrixClient, windowState: windowState))
    }
}

/// The confirmation of "Archive All Read" with the number of chats
/// (MATRIX-222). A system alert, so it has no snapshot test.
struct ArchiveAllReadConfirmation: ViewModifier {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    func body(content: Content) -> some View {
        let request = windowState.archiveAllRead
        content.alert(
            ChatListInboxFlow.archiveAllReadTitle(count: request?.count ?? 0),
            isPresented: Binding(
                get: { windowState.archiveAllRead != nil },
                set: { if !$0 { windowState.archiveAllRead = nil } }
            ),
            presenting: request
        ) { request in
            if request.count > 0 {
                Button("Archive") {
                    SidebarInbox.archiveAllRead(request, client: appState.matrixClient, windowState: windowState)
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { request in
            Text(ChatListInboxFlow.archiveAllReadMessage(count: request.count))
        }
    }
}

/// The sheet behind "Custom…" (MATRIX-207).
struct InboxDatePickerHost: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let request: InboxDatePickerRequest

    var body: some View {
        let client = appState.matrixClient
        InboxDatePickerSheet(kind: request.kind, chatName: request.chatName) { date in
            let action: InboxMenuAction = request.kind == .snooze ? .snooze(until: date) : .remind(at: date)
            SidebarInbox.perform(action, roomIds: request.roomIds, name: request.chatName, client: client, windowState: windowState)
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
            // MATRIX-225: the entrance settles it into place; it still
            // leaves by sliding down and fading.
            .entranceMotion()
            .transition(.asymmetric(insertion: .identity, removal: .move(edge: .bottom).combined(with: .opacity)))
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
