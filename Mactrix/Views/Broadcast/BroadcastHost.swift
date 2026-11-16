import Core
import Models
import SwiftUI
import UI

// MATRIX-168: the app-side glue for the broadcast (contract §11,
// 2026-11-16). The sheet's views live in `UI/Broadcast`, the rules in
// `Models` (`BroadcastTarget`, `BroadcastDraft`, `BroadcastRun`), and the
// send in `Core` (`MatrixClient.sendBroadcast(text:toRoom:)`).

/// What a window can broadcast to now.
@MainActor
enum SidebarBroadcast {
    /// The request for the window's rail filter, or nil when a broadcast is
    /// not available: the Inbox, a single-room window, no account, or a
    /// filter that shows no chat.
    ///
    /// The targets are the chats the sidebar shows now: the rail filter,
    /// narrowed by the chat-list filter (Unread, People). They are read
    /// once, here, so the list does not change while the sheet is open.
    static func request(client: MatrixClient?, windowState: WindowState) -> BroadcastRequest? {
        guard let client, !windowState.isSingleRoomWindow,
              let name = SidebarRail.filterName(client: client, windowState: windowState)
        else { return nil }
        let chats = SidebarView.visibleChatList(client: client, windowState: windowState)
        return request(
            filterName: name,
            items: chats.visible.ordered,
            filter: SidebarRail.filter(client: client, windowState: windowState)
        )
    }

    /// The request for rows the caller has already.
    static func request(filterName: String?, items: [ChatListItem], filter: ChatListRailFilter) -> BroadcastRequest? {
        guard let filterName else { return nil }
        let targets = BroadcastTarget.targets(items: items, filter: filter)
        return targets.isEmpty ? nil : BroadcastRequest(filterName: filterName, targets: targets)
    }
}

/// The key window's broadcast, for the File menu item.
struct BroadcastCommand: Equatable {
    /// The label's or the space's name, for the item title.
    let filterName: String
    /// Opens the sheet in the window.
    let open: @MainActor () -> Void

    /// The menu rebuilds only when the title changes. `open` reads the
    /// window's state when it runs.
    static func == (lhs: BroadcastCommand, rhs: BroadcastCommand) -> Bool {
        lhs.filterName == rhs.filterName
    }
}

extension FocusedValues {
    /// The key window's broadcast, published by `BroadcastCommandPublisher`.
    /// Nil when the window has nothing to broadcast to.
    @Entry var broadcastCommand: BroadcastCommand?
}

/// Publishes the window's `BroadcastCommand` for the File menu.
///
/// A modifier, as `GoNavigationPublisher`, so a room list change
/// re-evaluates only this body.
struct BroadcastCommandPublisher: ViewModifier {
    @Environment(AppState.self) private var appState
    let windowState: WindowState

    func body(content: Content) -> some View {
        content.focusedSceneValue(\.broadcastCommand, command)
    }

    private var command: BroadcastCommand? {
        let client = appState.matrixClient
        guard let request = SidebarBroadcast.request(client: client, windowState: windowState) else { return nil }
        return BroadcastCommand(filterName: request.filterName) { [windowState] in
            windowState.broadcast = SidebarBroadcast.request(client: client, windowState: windowState)
        }
    }
}

/// The broadcast sheet of one window: holds the draft and the run.
///
/// Nothing is stored: the draft and the run end with the sheet.
struct BroadcastHost: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let request: BroadcastRequest

    @State private var draft: BroadcastDraft
    @State private var typedCount = ""
    @State private var step: BroadcastSheetStep = .compose
    @State private var run: BroadcastRun?
    @State private var confirmsClose = false

    init(request: BroadcastRequest) {
        self.request = request
        self._draft = State(initialValue: BroadcastDraft(targets: request.targets))
    }

    var body: some View {
        BroadcastSheet(
            filterName: request.filterName,
            targets: request.targets,
            draft: $draft,
            typedCount: $typedCount,
            step: step,
            states: run?.states ?? [:],
            phase: run?.phase ?? .idle,
            imageLoader: appState.matrixClient,
            actions: actions
        )
        .confirmationDialog("Stop the broadcast?", isPresented: $confirmsClose) {
            Button("Stop and Close", role: .destructive) {
                run?.stop()
                dismiss()
            }
            Button("Continue", role: .cancel) {}
        } message: {
            Text("The chats that are still waiting get no message. Sent messages are not recalled.")
        }
        // The window closed, or the account signed out: no further send
        // starts. The send in flight finishes.
        .onDisappear {
            run?.stop()
        }
    }

    private var actions: BroadcastSheetActions {
        BroadcastSheetActions(
            review: {
                guard draft.canReview(targets: request.targets) else { return }
                typedCount = ""
                step = .review
            },
            back: {
                typedCount = ""
                step = .compose
            },
            send: start,
            stop: { run?.stop() },
            retryFailed: {
                guard let run else { return }
                Task { await run.retryFailed() }
            },
            close: {
                if run?.isActive == true {
                    confirmsClose = true
                } else {
                    dismiss()
                }
            }
        )
    }

    /// Starts the run. The review step's button is the one caller, and the
    /// confirm rule is checked again here.
    private func start() {
        let selected = draft.selectedTargets(in: request.targets)
        guard run == nil, draft.canReview(targets: request.targets),
              BroadcastConfirmation.isConfirmed(targetCount: selected.count, typedCount: typedCount),
              let client = appState.matrixClient
        else { return }
        let newRun = BroadcastRun(
            targets: selected,
            text: draft.outgoingText,
            send: { [weak client] target, text in
                guard let client else { throw BroadcastSendError.clientUnavailable }
                try await client.sendBroadcast(text: text, toRoom: target.roomId)
            },
            pause: {
                try? await Task.sleep(for: MatrixClient.broadcastPause)
            }
        )
        run = newRun
        step = .progress
        // Not tied to the view: a send in flight finishes if the sheet
        // closes. `stop()` ends the run.
        Task { await newRun.start() }
    }
}
