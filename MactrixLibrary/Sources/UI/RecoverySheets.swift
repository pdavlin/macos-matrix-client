import AppKit
import SwiftUI

extension EnvironmentValues {
    /// When true, busy-state views in this file show a determinate substitute
    /// instead of an indeterminate spinner.
    ///
    /// An indeterminate `ProgressView` animates on its own timer, so a snapshot
    /// capture lands on a random animation phase. Production code never sets
    /// this key; only snapshot tests do, to get one stable frame.
    @Entry var usesStaticProgressIndicators: Bool = false
}

/// Shows a freshly created recovery key, once.
///
/// The SDK returns the key exactly once from `enableRecovery`. Nothing stores
/// it: not the keychain, not the log, not a file. If the user dismisses this
/// without saving it, the only way to get another is `resetRecoveryKey`, which
/// invalidates the one they were just shown. That is why dismissal is gated on
/// an explicit acknowledgement rather than a close button.
public struct RecoveryKeyDisplaySheet: View {
    let recoveryKey: String
    let onAcknowledge: () -> Void

    @State private var confirmedSaved = false
    @State private var didCopy = false

    public init(recoveryKey: String, onAcknowledge: @escaping () -> Void) {
        self.recoveryKey = recoveryKey
        self.onAcknowledge = onAcknowledge
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Save your recovery key", systemImage: "key.horizontal.fill")
                .font(.title2)
                .bold()

            Text("""
            This key is the only way back into your encrypted history if you \
            lose access to this device. It is shown once and cannot be \
            retrieved later.
            """)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(recoveryKey)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(recoveryKey, forType: .string)
                didCopy = true
            } label: {
                Label(didCopy ? "Copied" : "Copy to clipboard", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }

            Toggle("I have saved this key somewhere safe", isOn: $confirmedSaved)

            HStack {
                Spacer()
                Button("Done") { onAcknowledge() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!confirmedSaved)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Collects a recovery key to unlock existing secret storage.
///
/// Reached when `RecoveryState` is `.incomplete`: storage exists on the server
/// but this device cannot read it, so encrypted history stays undecryptable
/// however many times the session is verified by SAS.
public struct RecoveryKeyEntrySheet: View {
    let isBusy: Bool
    let errorMessage: String?
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var enteredKey = ""
    @Environment(\.usesStaticProgressIndicators) private var usesStaticProgressIndicators

    public init(
        isBusy: Bool,
        errorMessage: String?,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    private var canSubmit: Bool {
        !isBusy && !enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Enter your recovery key", systemImage: "key.horizontal")
                .font(.title2)
                .bold()

            Text("This unlocks your encrypted history on this device. It is the key you saved when recovery was set up.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Recovery key", text: $enteredKey, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2 ... 4)
                .disabled(isBusy)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isBusy {
                    if usesStaticProgressIndicators {
                        // Snapshot-only: a determinate ring renders one fixed
                        // frame, unlike the indeterminate spinner below.
                        ProgressView(value: 0.5, total: 1.0)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Unlocking…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .disabled(isBusy)
                Button("Unlock") { onSubmit(enteredKey) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
