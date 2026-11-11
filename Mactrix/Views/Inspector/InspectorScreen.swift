import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

struct InspectorScreen: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    @ViewBuilder
    var content: some View {
        @Bindable var windowState = windowState

        switch windowState.inspectorContent {
        case .search:
            SearchInspectorView()
        case let .focusThread(threadTimeline: thread):
            VStack(spacing: 0) {
                UI.ThreadTimelineHeader {
                    windowState.inspectorVisible = false
                    Task {
                        // Insert sleep to delay UI update until close animation finishes
                        try? await Task.sleep(for: .milliseconds(500))
                        windowState.inspectorContent = .roomInfo
                    }
                }
                ChatView(timeline: thread)
            }
            .inspectorColumnWidth(min: 200, ideal: 400, max: nil)
        case .roomInfo:
            switch windowState.selectedScreen {
            case let .joinedRoom(timeline: timeline):
                UI.RoomInspectorView(
                    room: timeline.room,
                    members: timeline.room.members,
                    roomInfo: timeline.room.roomInfo,
                    imageLoader: appState.matrixClient,
                    inspectorVisible: $windowState.inspectorVisible
                ) {
                    mergeSection(roomId: timeline.room.id, isDirect: timeline.room.roomInfo?.isDirect == true)
                }
            case .mergedChat:
                // MATRIX-141 Phase B: the merged chat view (Wave 2) brings
                // its own inspector.
                Text("Merged chat details arrive in the next build")
                    .multilineTextAlignment(.center)
                    .padding()
                    .inspectorColumnWidth(min: 200, ideal: 250, max: nil)
            case .none, .newRoom, .newChat, .previewRoom, .loadMatrixUrl, .user:
                Text("No room selected")
                    .inspectorColumnWidth(min: 200, ideal: 250, max: nil)
            }
        case let .userInfo(userId: userId):
            InspectorUserInfo(userId: userId)
                .inspectorColumnWidth(min: 200, ideal: 250, max: nil)
        case .roomThreads:
            InspectorThreads()
                .inspectorColumnWidth(min: 200, ideal: 250, max: nil)
        case .roomPins:
            InspectorRoomPins()
                .inspectorColumnWidth(min: 200, ideal: 250, max: nil)
        }
    }

    /// MATRIX-141: "Merge with…" for a one-to-one chat; "Merged into
    /// <name>" with Edit and Unmerge for a member room.
    @ViewBuilder
    private func mergeSection(roomId: String, isDirect: Bool) -> some View {
        if let mergedChats = appState.matrixClient?.mergedChats {
            let status = RoomMergeStatus.of(roomId: roomId, isDirect: isDirect, document: mergedChats.document)
            if status != .unavailable {
                Section("Merged Chat") {
                    MergedChatInspectorSection(
                        status: status,
                        isEditable: mergedChats.isEditable,
                        onMerge: { windowState.mergeEditor = .create(roomId: roomId) },
                        onEdit: {
                            if case let .member(merge) = status {
                                windowState.mergeEditor = .edit(mergedChatId: merge.id)
                            }
                        },
                        onUnmerge: {
                            guard case let .member(merge) = status else { return }
                            Task {
                                let outcome = await mergedChats.unmerge(merge.id)
                                if outcome != .saved {
                                    let reason = String(describing: outcome)
                                    Logger.viewCycle.error("unmerge from the inspector did not land: \(reason, privacy: .public)")
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    var body: some View {
        @Bindable var windowState = windowState

        content
            .toolbar {
                Button {
                    windowState.toggleInspector()
                } label: {
                    Label("Toggle Inspector", systemImage: "info.circle")
                }
                .help("Toggle Inspector")
            }
    }
}
