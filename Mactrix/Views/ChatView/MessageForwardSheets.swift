import Core
import Models
import SwiftUI
import UI

/// The forward sheets of a room view (MATRIX-112, M2-B5, D-4).
///
/// The Forward action sets `LiveTimeline.forwarding`. This modifier then
/// shows, one after the other:
/// 1. the quick switcher in picker mode (rooms only, MATRIX-114);
/// 2. the confirmation with the room name, a preview, and the media size;
/// 3. an alert, if the forward fails.
///
/// The flow lives in the timeline, not in a row, because a row can scroll
/// away while a sheet is open. The SDK calls are in
/// `MatrixClient.forward(_:to:)`.
struct MessageForwardSheets: ViewModifier {
    @Environment(AppState.self) private var appState
    let timeline: LiveTimeline

    private var flow: LiveMessageForwardFlow {
        timeline.forwarding
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: pickingBinding, onDismiss: flow.sheetDidClose) { _ in
                QuickSwitcherContainerView(pickRoomFrom: timeline.room.id, onPick: pick)
            }
            .sheet(item: confirmingBinding, onDismiss: flow.sheetDidClose) { step in
                UI.MessageForwardSheet(
                    content: step.request.content,
                    roomName: step.target?.name,
                    isSending: flow.isSending,
                    onForward: confirm,
                    onCancel: flow.cancel
                )
            }
            .alert(
                "Could not forward the message",
                isPresented: Binding(
                    get: { flow.failure != nil },
                    set: { if !$0 { flow.clearFailure() } }
                ),
                presenting: flow.failure
            ) { _ in
                Button("OK", action: flow.clearFailure)
            } message: { failure in
                Text(failure)
            }
    }

    // MARK: - Bindings

    /// Escape or a click outside closes the picker with no pick.
    private var pickingBinding: Binding<LiveMessageForwardFlow.Step?> {
        Binding(
            get: { flow.picking },
            set: { if $0 == nil { flow.dismissPicker() } }
        )
    }

    private var confirmingBinding: Binding<LiveMessageForwardFlow.Step?> {
        Binding(
            get: { flow.confirming },
            set: { if $0 == nil { flow.cancel() } }
        )
    }

    // MARK: - Actions

    /// The picker hands back a room ID; the confirmation needs the room.
    private func pick(_ roomId: String) {
        guard let target = appState.matrixClient?.forwardTarget(roomId: roomId) else {
            flow.fail(String(localized: "The chosen room is not available."))
            return
        }
        flow.pick(target)
    }

    private func confirm() {
        guard let matrixClient = appState.matrixClient else {
            flow.fail(String(localized: "You are not signed in."))
            return
        }
        Task {
            await flow.confirm { request, target in
                try await matrixClient.forward(request, to: target)
            }
        }
    }
}

extension View {
    /// Adds the forward sheets for `timeline` (MATRIX-112).
    func messageForwardSheets(timeline: LiveTimeline) -> some View {
        modifier(MessageForwardSheets(timeline: timeline))
    }
}
