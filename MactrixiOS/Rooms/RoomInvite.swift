import Models
import OSLog
import SwiftUI

/// The accept and reject calls for one invited room, and their state
/// (MATRIX-104).
///
/// The calls come in as closures: the app passes the SDK calls of the Mac
/// `ChatView.invitedRoom`, tests pass stubs. The model owns no Matrix
/// semantics; it only runs one call at a time and keeps the result for the
/// view.
@MainActor @Observable
final class RoomInviteModel {
    /// The two answers to an invite.
    enum Action: Equatable {
        case accept
        case reject
    }

    /// A call that threw. The view shows it under the buttons until the next
    /// call starts.
    struct Failure: Equatable {
        let action: Action
        /// The SDK error, as the Mac logs it.
        let detail: String
    }

    /// The call in flight, if any.
    private(set) var running: Action?
    /// The call that succeeded. The screen changes after it (the timeline
    /// opens, or the room closes), so the buttons stay disabled.
    private(set) var completed: Action?
    /// The last call that threw, cleared when a new call starts.
    private(set) var failure: Failure?

    @ObservationIgnored private let acceptCall: @MainActor () async throws -> Void
    @ObservationIgnored private let rejectCall: @MainActor () async throws -> Void

    /// - Parameters:
    ///   - accept: Joins the room.
    ///   - reject: Leaves and forgets the room.
    init(
        accept: @escaping @MainActor () async throws -> Void,
        reject: @escaping @MainActor () async throws -> Void
    ) {
        acceptCall = accept
        rejectCall = reject
    }

    /// True while a call runs or after one succeeded: both buttons are
    /// disabled.
    var isBusy: Bool {
        running != nil || completed != nil
    }

    /// Whether the button for `action` shows progress.
    func showsProgress(for action: Action) -> Bool {
        running == action || completed == action
    }

    /// Runs the call for `action`.
    ///
    /// - Returns: True when the call succeeded. False when it threw, or when
    ///   the model was busy and the call did not run.
    @discardableResult
    func perform(_ action: Action) async -> Bool {
        guard !isBusy else { return false }
        running = action
        failure = nil
        defer { running = nil }

        do {
            switch action {
            case .accept:
                try await acceptCall()
            case .reject:
                try await rejectCall()
            }
            completed = action
            return true
        } catch {
            Logger.roomList.error("invite \(String(describing: action), privacy: .public) failed: \(error)")
            failure = Failure(action: action, detail: String(describing: error))
            return false
        }
    }
}

/// What the invite screen names, from the models the room list already has.
enum RoomInviteDetails {
    /// The inviter's display name or localpart, when the room's latest event
    /// is the invite and names who sent it. Nil otherwise.
    static func inviterName(latestEvent: Models.ChatListLatestEvent?) -> String? {
        guard let latestEvent, latestEvent.content == .invite else { return nil }
        let name = latestEvent.sender.name
        return name.isEmpty ? nil : name
    }
}

/// The screen for an invited room: the room name, who sent the invite, and
/// Accept and Reject (MATRIX-104).
///
/// An iOS view, not a shared one: the Mac `ChatView.invitedRoom` shows no
/// progress, error, or inviter, so a shared view would change the Mac.
struct RoomInviteView: View {
    let roomName: String
    let inviterName: String?
    /// Called after a call succeeded. The parent opens the timeline after
    /// `.accept` and closes the room after `.reject`.
    let onCompleted: @MainActor (RoomInviteModel.Action) -> Void

    @State private var model: RoomInviteModel

    init(
        roomName: String,
        inviterName: String?,
        model: @autoclosure () -> RoomInviteModel,
        onCompleted: @escaping @MainActor (RoomInviteModel.Action) -> Void
    ) {
        self.roomName = roomName
        self.inviterName = inviterName
        self.onCompleted = onCompleted
        _model = State(initialValue: model())
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "envelope.open")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(roomName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Group {
                    if let inviterName {
                        Text("\(inviterName) invited you to this room")
                    } else {
                        Text("You are invited to this room")
                    }
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    run(.accept)
                } label: {
                    buttonLabel("Accept Invite", action: .accept)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("inviteAcceptButton")

                Button(role: .destructive) {
                    run(.reject)
                } label: {
                    buttonLabel("Reject Invite", action: .reject)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("inviteRejectButton")
            }
            .controlSize(.large)
            .disabled(model.isBusy)
            .frame(maxWidth: 360)

            if let failure = model.failure {
                RoomInviteFailureView(failure: failure)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func buttonLabel(_ title: LocalizedStringKey, action: RoomInviteModel.Action) -> some View {
        HStack(spacing: 8) {
            if model.showsProgress(for: action) {
                ProgressView()
            }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func run(_ action: RoomInviteModel.Action) {
        Task {
            if await model.perform(action) {
                onCompleted(action)
            }
        }
    }
}

/// The error under the invite buttons.
private struct RoomInviteFailureView: View {
    let failure: RoomInviteModel.Failure

    var body: some View {
        VStack(spacing: 4) {
            Label(headline, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(failure.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inviteFailure")
    }

    private var headline: LocalizedStringKey {
        switch failure.action {
        case .accept:
            "Could not accept the invite."
        case .reject:
            "Could not reject the invite."
        }
    }
}

#if DEBUG
    #Preview("Invite") {
        NavigationStack {
            RoomInviteView(
                roomName: "#eng-platform (Slack)",
                inviterName: "Alex",
                model: RoomInviteModel(accept: {}, reject: {}),
                onCompleted: { _ in }
            )
            .navigationTitle("#eng-platform (Slack)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
#endif
