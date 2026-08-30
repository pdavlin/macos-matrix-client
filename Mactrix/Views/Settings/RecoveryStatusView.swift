import MatrixRustSDK
import OSLog
import SwiftUI
import UI

/// The recovery equivalent of `SessionVerificationStatusView`.
///
/// Verification and recovery answer different questions and both have to be
/// true for encrypted history to survive this device. Verification says other
/// people's clients trust this session. Recovery says the account's keys exist
/// somewhere this device — or a future one — can retrieve them from. S-07
/// mistook the first for the second, so these are presented separately rather
/// than folded into one "secure" indicator.
struct RecoveryStatusView: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme

    /// Compact form for the sidebar: renders nothing unless there is something
    /// to act on.
    let compact: Bool

    @State private var recovery = RecoveryProgress()
    @State private var showingEntry = false
    @State private var confirmingSetup = false

    init(compact: Bool = false) {
        self.compact = compact
    }

    private var encryption: Encryption? {
        appState.matrixClient?.client.encryption()
    }

    private var state: RecoveryState {
        appState.matrixClient?.recoveryState ?? .unknown
    }

    /// Whether the initial sync has finished.
    ///
    /// `RecoveryState` is derived from account data held in the local store.
    /// On a freshly logged-in session that store is empty, so
    /// `secret_storage().is_enabled()` reads false and the SDK reports a
    /// confident `disabled` — not `unknown` — for an account that does have
    /// recovery. Acting on that offers "Set up recovery" to someone who
    /// already has a key, and enabling replaces it.
    ///
    /// That happened on the dev account on 2026-08-30 and destroyed a recovery
    /// key the user had just saved. So no actionable recovery UI appears until
    /// the room list reports `.running`, the SDK's signal that the first sync
    /// completed and account data is present.
    private var hasCompletedInitialSync: Bool {
        appState.matrixClient?.roomListServiceState == .running
    }

    var body: some View {
        Group {
            switch state {
            case .unknown:
                // Reads `unknown` until the first sync settles. Saying anything
                // here would flash a warning on every launch.
                EmptyView()
            case .enabled:
                if !compact { enabledRow }
            case .disabled:
                if hasCompletedInitialSync {
                    actionable(
                        icon: "exclamationmark.shield",
                        title: "Recovery is not set up",
                        detail: "Without it, your encrypted history cannot be restored if you lose this device.",
                        button: "Set up recovery…"
                    ) {
                        confirmingSetup = true
                    }
                }
            case .incomplete:
                if hasCompletedInitialSync {
                    actionable(
                        icon: "key.horizontal",
                        title: "Recovery key needed",
                        detail: "Your account has a backup this device cannot read yet. Enter your recovery key to unlock it.",
                        button: "Enter recovery key…"
                    ) {
                        showingEntry = true
                    }
                }
            }
        }
        // Setting up recovery is destructive when recovery already exists:
        // `enableRecovery` replaces secret storage, and every previously
        // issued key stops working. The state check above should prevent that,
        // but it is derived from synced data and was wrong once already, so
        // the user gets the last word.
        .alert("Set up recovery?", isPresented: $confirmingSetup) {
            Button("Set up recovery", role: .destructive) {
                Task { if let encryption { await recovery.enable(using: encryption) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
            This creates a new recovery key and shows it once.

            If this account already has a recovery key, that key will stop \
            working. Only continue if you do not have one.
            """)
        }
        .sheet(isPresented: .init(get: { recovery.pendingRecoveryKey != nil }, set: { _ in })) {
            if let key = recovery.pendingRecoveryKey {
                RecoveryKeyDisplaySheet(recoveryKey: key) { recovery.acknowledgeKey() }
            }
        }
        .sheet(isPresented: $showingEntry) {
            RecoveryKeyEntrySheet(
                isBusy: recovery.isBusy,
                errorMessage: errorText,
                onSubmit: { key in
                    Task {
                        if let encryption { await recovery.recover(with: key, using: encryption) }
                        if case .recovered = recovery.phase { showingEntry = false }
                    }
                },
                onCancel: {
                    recovery.dismissError()
                    showingEntry = false
                }
            )
        }
    }

    private var errorText: String? {
        if case let .failed(message) = recovery.phase {
            message
        } else { nil }
    }

    @ViewBuilder
    private var enabledRow: some View {
        HStack {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.2)))
                .foregroundStyle(Color.green.mix(with: colorScheme == .light ? .black : .white, by: 0.2))
            VStack(alignment: .leading) {
                Text("Recovery is set up")
                    .font(.title3)
                Text("Your encrypted history can be restored on a new device.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actionable(
        icon: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        button: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        VStack {
            Label {
                Text(title).bold()
                Text(detail).lineLimit(9)
            } icon: {
                Image(systemName: icon).bold()
            }
            .labelStyle(.multiline)
            .frame(maxWidth: .infinity)

            HStack {
                if case let .enabling(detail) = recovery.phase {
                    ProgressView().controlSize(.small)
                    Text(detail).foregroundStyle(.secondary)
                } else if let errorText, !showingEntry {
                    Text(errorText).foregroundStyle(.red).lineLimit(3)
                }
                Button(button, action: action)
                    .disabled(recovery.isBusy)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.2))
        .foregroundStyle(Color.orange.mix(with: colorScheme == .light ? .black : .white, by: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
