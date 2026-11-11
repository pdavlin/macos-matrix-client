import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI
import Utils

struct MainView: View {
    @Environment(AppState.self) var appState

    @SceneStorage("MainView.windowState")
    private var windowState: WindowState = .init()

    @State private var showWelcomeSheet: Bool = false
    /// The ⌘K quick switcher (MATRIX-114), toggled from the Go menu.
    @State private var showQuickSwitcher: Bool = false

    @ViewBuilder var details: some View {
        switch windowState.selectedScreen {
        case .joinedRoom(timeline: let timeline):
            ChatView(timeline: timeline).id(timeline.room.id)
        case .previewRoom(let room):
            UI.RoomPreviewView(
                preview: room.info(),
                imageLoader: appState.matrixClient,
                actions: appState.matrixClient?.roomPreviewActions(forRoomWithId: room.info().roomId, windowState: windowState)
            )
        case .newRoom:
            UI.CreateRoomScreen(onSubmit: { params in
                guard let matrixClient = appState.matrixClient else { return }
                let newRoom = try await matrixClient.client.createRoom(request: params.asMatrixRequest)
                windowState.selectedRoomId = newRoom
            })
        case .newChat(let mode):
            NewChatContainerView(mode: mode, openRoom: openRoom)
        case .loadMatrixUrl(let matrixUri):
            LoadMatrixUriScreen(matrixUri: matrixUri)
        case .mergedChat(let mergedChatId):
            MergedChatDetailContainer(mergedChatId: mergedChatId)
        case .user(profile: let profile):
            UserProfileView(
                profile: profile,
                isUserIgnored: appState.matrixClient?.isUserIgnored(profile.userId) ?? false,
                actions: appState.matrixClient?.userProfileActions(forUserId: profile.userId, windowState: windowState),
                timelineActions: nil,
                imageLoader: appState.matrixClient
            )
        case .none:
            ContentUnavailableView("Select a room", systemImage: "message.fill")
        }
    }

    var verificationSheetPresented: Binding<Bool> {
        Binding(
            get: { appState.matrixClient?.sessionVerificationData != nil },
            set: { isPresented in
                if !isPresented {
                    Task {
                        do {
                            try await appState.matrixClient?.client.getSessionVerificationController().declineVerification()
                        } catch {
                            Logger.viewCycle.error("failed to decline verification: \(error)")
                            appState.matrixClient?.sessionVerificationData = nil
                        }
                    }
                }
            }
        )
    }

    var body: some View {
        @Bindable var windowState = windowState

        NavigationSplitView(
            sidebar: { SidebarView() },
            detail: { details }
        )
        .inspector(isPresented: $windowState.inspectorVisible, content: {
            InspectorScreen()
                .environment(windowState)
        })
        .task { await attemptLoadUserSession() }
        .sheet(isPresented: $showWelcomeSheet, onDismiss: onLoginModalDismiss) {
            WelcomeSheetView()
        }
        .sheet(isPresented: verificationSheetPresented, content: {
            if let verificationData = appState.matrixClient?.sessionVerificationData {
                UI.SessionVerificationModal(verificationData: verificationData.asModel, onComplete: { response in
                    Task {
                        switch response {
                        case .accept:
                            do {
                                try await appState.matrixClient?.client.getSessionVerificationController().approveVerification()
                            } catch {
                                Logger.viewCycle.error("failed to approve verification: \(error)")
                                appState.matrixClient?.sessionVerificationData = nil
                            }
                        case .decline:
                            do {
                                try await appState.matrixClient?.client.getSessionVerificationController().declineVerification()
                            } catch {
                                Logger.viewCycle.error("failed to decline verification: \(error)")
                                appState.matrixClient?.sessionVerificationData = nil
                            }
                        }
                    }
                })
            }
        })
        .sheet(isPresented: $showQuickSwitcher) {
            QuickSwitcherContainerView(openRoom: openRoom)
                .environment(windowState)
        }
        .onChange(of: appState.matrixClient == nil) { _, matrixClientIsNil in
            if matrixClientIsNil {
                Logger.viewCycle.info("Matrix client is nil, present welcome sheet")
                showWelcomeSheet = true
                // The client and its room handles are torn down; drop the selection so the
                // detail pane doesn't stay bound to a dead room.
                windowState.chatSelection = nil
                windowState.selectedScreen = .none
            }
        }
        .task(id: windowState.chatSelection) {
            await onRoomSelected()
        }
        // MATRIX-141: a merge, an unmerge, or the first read of the merged
        // chats can move the selection (a member room shows its merged chat;
        // an unmerged chat shows its default room).
        .onChange(of: appState.matrixClient?.mergedChats?.document) { previous, current in
            // No model: signed out. The client handler above clears the
            // selection; moving it to a member room here would open a room
            // on a client that is going away.
            guard let current else { return }
            let resolved = MergedChatSelection.resolve(
                windowState.chatSelection,
                document: current,
                previous: previous ?? MergedChatDocument()
            )
            if resolved != windowState.chatSelection {
                windowState.chatSelection = resolved
            }
        }
        .modifier(MergeChatsSheetPresenter(windowState: windowState))
        .onChange(of: appState.matrixClient?.authenticationFailed) { _, authFailed in
            if authFailed == true {
                Logger.viewCycle.info("Auth failed: tearing down the session and presenting sign-in")
                // Full reset, not just dropping the reference: the FFI handle
                // maps keep the sync machinery alive otherwise, and the stale
                // keychain session would reproduce the auth error on the next
                // launch (MATRIX-48).
                Task { try? await appState.reset() }
            }
        }
        .onOpenURL { url in
            Logger.viewCycle.debug("onOpenUrl \(url)")

            do {
                let matrixUri = try Utils.MatrixUriScheme(parseUrl: url.absoluteString)
                Logger.viewCycle.info("Matched Matrix Uri")

                windowState.selectedScreen = .loadMatrixUrl(matrixUri)
            } catch {
                Logger.viewCycle.error("Failed to parse Matrix Uri: \(error)")
            }
        }
        .onChange(of: appState.matrixClient?.rooms.count) { _, _ in
            // The room list can hydrate after a room was already selected (for
            // example a restored selection right after launch, before sync has
            // populated the room store). Re-resolve so the timeline opens once
            // the room becomes available instead of staying stuck on preview.
            guard windowState.selectedRoomId != nil, case .previewRoom = windowState.selectedScreen else { return }
            Task { await onRoomSelected() }
        }
        .modifier(ToolbarViewModifier())
        .modifier(SearchViewModifier())
        .environment(windowState)
        .focusedSceneValue(windowState)
        // Only a signed-in window offers ⌘K.
        .focusedSceneValue(\.quickSwitcherPresented, appState.matrixClient == nil ? nil : $showQuickSwitcher)
        // ⌘1…⌘9 and ⇧⌘] / ⇧⌘[ in the Go menu (MATRIX-115).
        .modifier(GoNavigationPublisher(windowState: windowState))
    }

    func attemptLoadUserSession() async {
        guard appState.matrixClient == nil else { return }

        // Restores the session and starts sync. Shared with room windows
        // restored on relaunch (MATRIX-116), so it runs once.
        await appState.restoreSavedSession()

        showWelcomeSheet = appState.matrixClient == nil
        // check if a room is selected and load it
        await onRoomSelected()
    }

    func onMatrixLoaded(matrixClient: MatrixClient) {
        Task {
            do {
                try await matrixClient.startSync()

                // check if a room is selected and load it
                await onRoomSelected()
            } catch {
                // Sync state stays at its pre-start value (.terminated, or
                // .error/.offline if the SDK reported one before the throw), so
                // the sidebar's "Restart sync" button (SidebarSyncStateView) is
                // already visible and wired to retry startSync() — no separate
                // failure UI needed here (MATRIX-56).
                Logger.viewCycle.error("Failed to start sync: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func onLoginModalDismiss() {
        Task {
            try await Task.sleep(for: .milliseconds(100))
            if let matrixClient = appState.matrixClient {
                onMatrixLoaded(matrixClient: matrixClient)
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    /// Shows `roomId`, or its merged chat when the room is a member
    /// (MATRIX-141), leaving whatever screen is up.
    ///
    /// Setting the selection alone is not enough when it is already selected
    /// (for example a New Chat that resolves to the DM the window last
    /// showed): `.task(id:)` does not fire for an unchanged value.
    func openRoom(_ roomId: String) async {
        let document = appState.matrixClient?.mergedChats?.document ?? MergedChatDocument()
        let target = MergedChatSelection.selection(showing: roomId, document: document)
        if windowState.chatSelection == target {
            await onRoomSelected()
        } else {
            windowState.chatSelection = target
        }
    }

    func onRoomSelected() async {
        guard let matrixClient = appState.matrixClient else { return }

        // MATRIX-141: every path that selects a room (a click, a
        // notification, a matrix: URL, ⌘K, the Go menu, restoration) lands
        // here. A member room moves to its merged chat; the task then runs
        // again for the new selection.
        let resolved = MergedChatSelection.resolve(
            windowState.chatSelection,
            document: matrixClient.mergedChats?.document ?? MergedChatDocument()
        )
        if resolved != windowState.chatSelection {
            windowState.chatSelection = resolved
            return
        }
        if let mergedChatId = windowState.selectedMergedChatId {
            windowState.selectedScreen = .mergedChat(id: mergedChatId)
            return
        }

        do {
            Logger.viewCycle.debug("Selected room: \(windowState.selectedRoomId.debugDescription)")

            if let roomId = windowState.selectedRoomId {
                // Prefer the Room already delivered by the room list service: the
                // client's room store (getRoom) may not have hydrated a joined
                // room yet, especially right after launch, even though the room
                // is already known to the sidebar.
                if let sidebarRoom = matrixClient.rooms.first(where: { $0.id == roomId }) {
                    windowState.selectedScreen = .joinedRoom(timeline: LiveTimeline(room: LiveRoom(matrixRoom: sidebarRoom.room)))
                } else if let selectedRoom = try matrixClient.client.getRoom(roomId: roomId) {
                    windowState.selectedScreen = .joinedRoom(timeline: LiveTimeline(room: LiveRoom(matrixRoom: selectedRoom)))
                } else {
                    let roomPreview = try await matrixClient.client.getRoomPreviewFromRoomId(roomId: roomId, viaServers: ["matrix.org"])

                    Logger.viewCycle.debug("Selected room preview: \(roomPreview.info().debugDescription)")
                    windowState.selectedScreen = .previewRoom(roomPreview)
                }
            } else {
                windowState.selectedScreen = .none
            }
        } catch {
            Logger.viewCycle.error("Failed to get room \(error)")
        }
    }
}
