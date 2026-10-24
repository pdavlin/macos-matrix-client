import Models
import SwiftUI
import UI

// MATRIX-77: the app-side glue for chat labels. The views live in
// `UI/Labels`; these wrappers bind them to `LabelsModel` and `WindowState`.

/// The label rail at the leading edge of the sidebar.
struct SidebarLabelRail: View {
    @Environment(WindowState.self) private var windowState

    let labels: LabelsModel?

    var body: some View {
        let document = labels?.document ?? ChatLabelDocument()
        // An ID the labels do not hold shows the Inbox: see
        // `WindowState.selectedLabelId`.
        let selection = windowState.selectedLabelId.flatMap { document.label(id: $0)?.id }

        LabelRail(
            labels: document.labels,
            badges: labels?.badges ?? [:],
            selection: selection,
            isEditable: labels?.isEditable ?? false,
            actions: actions
        )
    }

    private var actions: LabelRailActions {
        LabelRailActions(
            select: { windowState.selectedLabelId = $0 },
            newLabel: { windowState.labelEditor = .create(preselectedRoomId: nil) },
            edit: { windowState.labelEditor = .edit(labelId: $0.id) },
            toggleMute: { label in
                let muted = !label.isMuted
                labels?.mutate { $0.setMuted(label.id, muted) }
            },
            toggleShowInInbox: { label in
                let visibility: ChatLabelInboxVisibility = label.isShownInInbox ? .hidden : .all
                labels?.mutate { $0.setInboxVisibility(label.id, visibility) }
            },
            delete: { label in
                if windowState.selectedLabelId == label.id {
                    windowState.selectedLabelId = nil
                }
                labels?.mutate { $0.delete(label.id) }
            }
        )
    }
}

/// The "Add to a Label" submenu of a chat's context menu.
struct AddToLabelMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let roomId: String

    var body: some View {
        if let labels = appState.matrixClient?.labels {
            Menu {
                ForEach(labels.document.labels) { label in
                    Toggle(
                        isOn: Binding(
                            get: { label.rooms.contains(roomId) },
                            set: { isOn in
                                // State the wanted membership, not a toggle:
                                // the write applies to the newest document.
                                labels.mutate { document in
                                    if isOn {
                                        document.addRoom(roomId, to: label.id)
                                    } else {
                                        document.removeRoom(roomId, from: label.id)
                                    }
                                }
                            }
                        )
                    ) {
                        Label(label.name, systemImage: label.icon ?? "tag")
                    }
                }
                if !labels.document.labels.isEmpty {
                    Divider()
                }
                Button("New Label…") {
                    windowState.labelEditor = .create(preselectedRoomId: roomId)
                }
            } label: {
                Label("Add to a Label", systemImage: "tag")
            }
            .disabled(!labels.isEditable)
        }
    }
}

/// The Create/Edit Label sheet, with the chats to pick from.
struct LabelEditorHost: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let request: LabelEditorRequest

    @State private var directory = LabelChatDirectory()

    var body: some View {
        let labels = appState.matrixClient?.labels
        Group {
            switch request {
            case let .create(roomId):
                sheet(isNew: true, draft: ChatLabelDraft(rooms: roomId.map { [$0] } ?? [])) { draft in
                    labels?.mutate { document in
                        document.create(name: draft.name, colorIndex: draft.colorIndex, icon: draft.icon, rooms: draft.rooms)
                    }
                }
            case let .edit(labelId):
                if let label = labels?.document.label(id: labelId) {
                    sheet(isNew: false, draft: ChatLabelDraft(label: label)) { draft in
                        labels?.mutate { $0.apply(draft, to: labelId) }
                    }
                } else {
                    // Deleted elsewhere while the sheet was opening.
                    VStack(spacing: 16) {
                        ContentUnavailableView("This label no longer exists", systemImage: "tag.slash")
                        Button("Close") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(20)
                    .frame(width: 320)
                }
            }
        }
        .task {
            guard let roomListService = appState.matrixClient?.roomListService else { return }
            await directory.start(roomListService: roomListService)
        }
        .onDisappear {
            directory.stop()
        }
    }

    private func sheet(isNew: Bool, draft: ChatLabelDraft, save: @escaping (ChatLabelDraft) -> Void) -> some View {
        LabelEditSheet(
            isNew: isNew,
            draft: draft,
            chats: directory.chats,
            imageLoader: appState.matrixClient,
            onCancel: { dismiss() },
            onSave: { draft in
                save(draft)
                dismiss()
            }
        )
    }
}
