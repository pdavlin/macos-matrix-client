import Core
import MatrixRustSDK
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
    /// The name of the window's rail filter, or nil when a broadcast is not
    /// available: the Inbox, a single-room window, no account, or a filter
    /// with no chat.
    ///
    /// Cheap: the sidebar and the File menu read it on each update. It does
    /// not depend on the chat-list filter (Unread, People).
    static func filterName(client: MatrixClient?, windowState: WindowState) -> String? {
        guard let client, !windowState.isSingleRoomWindow,
              let name = SidebarRail.filterName(client: client, windowState: windowState),
              SidebarRail.narrowingRoomIds(client: client, windowState: windowState)?.isEmpty == false
        else { return nil }
        return name
    }

    /// The request for the window's rail filter, or nil when a broadcast is
    /// not available or the account holds no chat of the filter.
    ///
    /// MATRIX-172: the targets are every chat of the rail filter that the
    /// account has. They come from the account's unfiltered room list (the
    /// Dock badge tracker's), so the sidebar's page and the chat-list filter
    /// (Unread, People) do not narrow them. `BroadcastTargetList.make` has
    /// the rule. They are read once, here, so the list does not change
    /// while the sheet is open.
    static func request(client: MatrixClient?, windowState: WindowState) -> BroadcastRequest? {
        guard let client, let name = filterName(client: client, windowState: windowState) else { return nil }
        // `listedRooms` (MATRIX-171) holds each room when the SDK lists it;
        // `chats` gets a room after its room info is read.
        let tracker = client.dockBadge.unreadChats
        let source = BroadcastChatSource(
            sidebarEntries: client.chatListEntries(rooms: client.chatRooms),
            accountChatIds: Set(tracker.chats.keys).union(tracker.listedRooms.map { $0.room.id() }),
            accountListLimit: Int(UnreadChatsTracker.pageSize),
            row: { client.chatListRow(forRoomId: $0) }
        )
        let list = BroadcastTargetList.make(
            source: source,
            filter: SidebarRail.filter(client: client, windowState: windowState),
            labels: client.labels?.document ?? ChatLabelDocument(),
            spaces: client.roomAccounts.spaceMap,
            document: client.mergedChats?.document ?? MergedChatDocument()
        )
        return list.targets.isEmpty ? nil : BroadcastRequest(filterName: name, targets: list.targets, gap: list.gap)
    }
}

/// The key window's broadcast, for the File menu item.
struct BroadcastCommand: Equatable {
    /// The label's or the space's name, for the item title.
    let filterName: String
    /// The window the sheet opens in.
    let windowState: WindowState
    /// Opens the sheet in the window.
    let open: @MainActor () -> Void

    /// The menu rebuilds only when the title or the window changes. `open`
    /// reads the window's state and the client when it runs, because
    /// SwiftUI keeps the old command while each new one is equal to it
    /// (MATRIX-235).
    static func == (lhs: BroadcastCommand, rhs: BroadcastCommand) -> Bool {
        lhs.filterName == rhs.filterName && lhs.windowState === rhs.windowState
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
        guard let name = SidebarBroadcast.filterName(client: appState.matrixClient, windowState: windowState) else { return nil }
        return BroadcastCommand(filterName: name, windowState: windowState) { [appState, windowState] in
            windowState.broadcast = SidebarBroadcast.request(client: appState.matrixClient, windowState: windowState)
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
            gap: request.gap,
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
