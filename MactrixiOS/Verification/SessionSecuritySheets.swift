import Core
import SwiftUI
import UI

/// Presents the verification and recovery sheets for a signed-in session.
///
/// Sheets are navigation layer, so the system glass applies there. The
/// recovery sheets are the shared `UI` views the Mac app uses.
struct SessionSecuritySheets: ViewModifier {
    let model: SessionSecurityModel

    func body(content: Content) -> some View {
        @Bindable var model = model

        content
            .sheet(isPresented: verificationPresented) {
                if let data = model.verificationData {
                    EmojiVerificationSheet(data: data) { match in
                        Task { await model.answerVerification(match: match) }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            // Setup is destructive when recovery already exists: enabling
            // replaces secret storage and every earlier key stops working.
            // The state check is from synced data and was wrong once (S-25),
            // so the user confirms first. Same text as the Mac.
            .alert("Set up recovery?", isPresented: $model.confirmingRecoverySetup) {
                Button("Set Up Recovery", role: .destructive) {
                    Task { await model.enableRecovery() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("""
                This creates a new recovery key and shows it once.

                If this account already has a recovery key, that key will stop \
                working. Only continue if you do not have one.
                """)
            }
            .sheet(isPresented: keyDisplayPresented) {
                if let key = model.recovery.pendingRecoveryKey {
                    ScrollView {
                        RecoveryKeyDisplaySheet(recoveryKey: key) { model.recovery.acknowledgeKey() }
                    }
                    // The key is shown once. Dismissal goes through the
                    // "I have saved this key" confirmation only.
                    .interactiveDismissDisabled()
                }
            }
            .sheet(isPresented: $model.showingRecoveryKeyEntry, onDismiss: model.recovery.dismissError) {
                ScrollView {
                    RecoveryKeyEntrySheet(
                        isBusy: model.recovery.isBusy,
                        errorMessage: model.recoveryErrorMessage,
                        onSubmit: { key in Task { await model.recover(with: key) } },
                        onCancel: { model.cancelRecoveryKeyEntry() }
                    )
                }
                .interactiveDismissDisabled(model.recovery.isBusy)
            }
    }

    /// A swipe-down on the SAS sheet counts as "they do not match", as a
    /// closed sheet does on the Mac. The SDK then cancels the flow.
    private var verificationPresented: Binding<Bool> {
        Binding(
            get: { model.verificationData != nil },
            set: { isPresented in
                if !isPresented, model.verificationData != nil {
                    Task { await model.answerVerification(match: false) }
                }
            }
        )
    }

    private var keyDisplayPresented: Binding<Bool> {
        Binding(get: { model.recovery.pendingRecoveryKey != nil }, set: { _ in })
    }
}

extension View {
    func sessionSecuritySheets(model: SessionSecurityModel) -> some View {
        modifier(SessionSecuritySheets(model: model))
    }
}
