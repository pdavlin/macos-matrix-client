import Core
import Models
import SwiftUI
import UI

/// Shows the Merge Chats sheet a window asks for (`WindowState.mergeEditor`,
/// MATRIX-141). Main windows and room windows both carry it, so "Merge
/// with…" and "Edit Merged Chat…" work from either inspector.
struct MergeChatsSheetPresenter: ViewModifier {
    @Environment(AppState.self) private var appState
    let windowState: WindowState

    func body(content: Content) -> some View {
        @Bindable var windowState = windowState
        content
            .sheet(item: $windowState.mergeEditor) { request in
                sheet(for: request)
                    .environment(windowState)
            }
    }

    @ViewBuilder
    private func sheet(for request: MergedChatEditorRequest) -> some View {
        let client = appState.matrixClient
        switch request {
        case let .create(roomId):
            let row = client?.chatListRow(forRoomId: roomId)
            MergeChatsSheetHost(
                mode: .create,
                mergedChatId: UUID().uuidString,
                draft: row.map { MergedChatDraft(chats: [$0]) } ?? MergedChatDraft(rooms: [roomId])
            )
        case let .edit(mergedChatId):
            if let merge = client?.mergedChats?.merge(id: mergedChatId) {
                MergeChatsSheetHost(mode: .edit, mergedChatId: mergedChatId, draft: MergedChatDraft(merge: merge))
            } else {
                MergedChatMissingView()
            }
        }
    }
}

/// The Merge Chats sheet wired to the account (MATRIX-141).
///
/// It owns the draft, builds the member rows from the client, opens the
/// quick switcher in picker mode for "Add Chat…", and writes through
/// `MergedChatsModel`. A write that does not land keeps the sheet open with
/// an inline error.
struct MergeChatsSheetHost: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss

    let mode: MergeChatsSheet.Mode

    /// The ID the sheet writes. Kept in state, so a new merged chat keeps
    /// the UUID it got when the sheet opened.
    @State private var mergedChatId: String
    @State private var draft: MergedChatDraft
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var isPickingChat = false

    /// - Parameters:
    ///   - mode: create or edit.
    ///   - mergedChatId: a new UUID string to create, the merged chat's ID
    ///     to edit.
    ///   - draft: the starting draft.
    init(mode: MergeChatsSheet.Mode, mergedChatId: String, draft: MergedChatDraft) {
        self.mode = mode
        _mergedChatId = State(initialValue: mergedChatId)
        _draft = State(initialValue: draft)
    }

    private var mergedChats: MergedChatsModel? {
        appState.matrixClient?.mergedChats
    }

    /// The rows of the draft's chats.
    private var chats: [ChatListRowModel] {
        guard let client = appState.matrixClient else { return [] }
        return draft.rooms.compactMap { client.chatListRow(forRoomId: $0) }
    }

    var body: some View {
        MergeChatsSheet(
            mode: mode,
            draft: $draft,
            chats: chats,
            imageLoader: appState.matrixClient,
            onAddChat: { isPickingChat = true },
            onCancel: { dismiss() },
            onSubmit: submit,
            onUnmerge: unmerge,
            errorMessage: errorMessage,
            isBusy: isBusy
        )
        .sheet(isPresented: $isPickingChat) {
            QuickSwitcherContainerView(pickRoomFrom: nil, offering: isOffered) { roomId in
                draft.add(roomId)
            }
            .environment(windowState)
        }
    }

    /// The "Add Chat…" picker lists one-to-one chats that are not in the
    /// draft and not in another merged chat (`MergedChatPicking`).
    private func isOffered(_ room: QuickSwitcherRoom) -> Bool {
        MergedChatPicking.offers(
            roomId: room.id,
            isDirect: room.isDirect,
            draft: draft,
            editingId: mode == .edit ? mergedChatId : nil,
            document: mergedChats?.document ?? MergedChatDocument()
        )
    }

    private func submit(_ submitted: MergedChatDraft) {
        guard let mergedChats else { return }
        let id = mergedChatId
        run {
            await mergedChats.save(submitted, as: id)
        } onSaved: {
            // A main window shows the merged chat it just made.
            if mode == .create, !windowState.isSingleRoomWindow {
                windowState.chatSelection = .merged(id)
            }
        }
    }

    private func unmerge() {
        guard let mergedChats else { return }
        let id = mergedChatId
        run {
            await mergedChats.unmerge(id)
        } onSaved: {}
    }

    /// Runs one write with the buttons disabled. The sheet closes when it
    /// lands and shows why when it does not.
    private func run(_ write: @escaping () async -> MergedChatWriteOutcome, onSaved: @escaping () -> Void) {
        isBusy = true
        errorMessage = nil
        Task {
            let outcome = await write()
            isBusy = false
            switch outcome {
            case .saved:
                onSaved()
                dismiss()
            case .notEditable:
                errorMessage = String(
                    localized: "The merged chats come from a newer app version or cannot be read, so this version does not change them."
                )
            case .failed:
                errorMessage = String(localized: "The merged chat could not be saved. Check the connection and try again.")
            }
        }
    }
}

/// The Edit sheet of a merged chat that was removed (on another device, for
/// example) while the sheet opened.
private struct MergedChatMissingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView("This merged chat no longer exists", systemImage: "rectangle.stack.badge.minus")
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 320)
    }
}
