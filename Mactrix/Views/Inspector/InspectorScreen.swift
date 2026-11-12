import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

struct InspectorScreen: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    /// What the inspector shows. A merged chat has no thread list and no pin
    /// list (MATRIX-149), so a panel left open from a room shows the merged
    /// chat's details there.
    private var shownContent: InspectorContent {
        let content = windowState.inspectorContent
        if case .mergedChat = windowState.selectedScreen, content == .roomThreads || content == .roomPins {
            return .roomInfo
        }
        return content
    }

    @ViewBuilder
    var content: some View {
        @Bindable var windowState = windowState

        switch shownContent {
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
            case let .mergedChat(id: mergedChatId):
                MergedChatInspector(mergedChatId: mergedChatId)
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

/// The inspector of a selected merged chat (MATRIX-149): the live merged
/// chat from the account data, with its member chats' rows.
///
/// A merged chat the document does not hold (it was removed on another
/// device) shows the empty state, as the detail area does.
private struct MergedChatInspector: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let mergedChatId: String

    var body: some View {
        if let client = appState.matrixClient, let merge = client.mergedChats?.merge(id: mergedChatId) {
            let members = memberRows(of: merge, client: client)
            let mergedRow = ChatListMerging.entry(for: merge, members: members.map { ChatListEntry(row: $0) })?.row
                ?? ChatListRowModel(id: merge.id, title: merge.name, isDirect: true)
            UI.MergedChatInspectorView(
                mergedRow: mergedRow,
                members: members,
                memberDetails: client.mergedMemberDetails(for: members),
                imageLoader: client,
                isEditable: client.mergedChats?.isEditable ?? false,
                onEdit: { windowState.mergeEditor = .edit(mergedChatId: merge.id) }
            )
            // MATRIX-147: the workspace of each member chat, read once per room.
            .task(id: merge.rooms) {
                client.loadRoomAccounts(merge.rooms)
            }
        } else {
            Text("No room selected")
        }
    }

    /// One row per member room, in member order. A room the client does not
    /// know shows by its room ID, as in the Merge Chats sheet.
    private func memberRows(of merge: MergedChat, client: MatrixClient) -> [ChatListRowModel] {
        var seen = Set<String>()
        return merge.rooms
            .filter { seen.insert($0).inserted }
            .map { client.chatListRow(forRoomId: $0) ?? ChatListRowModel(id: $0, title: $0) }
    }
}
