import Core
import MatrixRustSDK
import Models
import SwiftUI
import UI

/// Wires `UI.NewChatScreen` to the signed-in client (MATRIX-75).
///
/// The mode lives in `WindowState.selectedScreen`, so the File menu and the
/// screen's own "New Group" and "Join a Matrix room" rows drive one value.
struct NewChatContainerView: View {
    @Environment(AppState.self) var appState
    @Environment(WindowState.self) var windowState

    let mode: NewChatMode
    /// What a Matrix link put in the draft (MATRIX-203), or nil. A new
    /// prefill starts a new draft.
    let prefill: NewChatPrefill?
    /// Shows a room in this window once it is opened, created, or joined.
    let openRoom: (_ roomId: String) async -> Void

    private var modeBinding: Binding<NewChatMode> {
        Binding(
            get: { mode },
            set: { windowState.selectedScreen = .newChat(mode: $0, prefill: prefill) }
        )
    }

    private var draft: NewChatDraft {
        switch prefill {
        case let .joinAddress(address): NewChatDraft(joinAddress: address)
        case let .person(person): NewChatDraft(selected: [person])
        case nil: NewChatDraft()
        }
    }

    var body: some View {
        if let matrixClient = appState.matrixClient {
            UI.NewChatScreen(
                mode: modeBinding,
                recentContacts: matrixClient.recentDirectContacts(limit: 8),
                ownUserId: try? matrixClient.client.userId(),
                imageLoader: matrixClient,
                actions: NewChatActions(
                    search: { try await matrixClient.searchNewChatPeople(query: $0) },
                    resolveProfile: { try await matrixClient.newChatProfile(userId: $0) },
                    start: { request in
                        let roomId = try await matrixClient.startChat(request)
                        await openRoom(roomId)
                    },
                    join: { address in
                        let roomId = try await matrixClient.joinNewChatRoom(address: address)
                        await openRoom(roomId)
                    }
                ),
                draft: draft
            )
            .id(prefill)
        } else {
            ContentUnavailableView("Not signed in", systemImage: "person.crop.circle.badge.exclamationmark")
        }
    }
}
