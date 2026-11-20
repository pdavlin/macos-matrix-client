import Models
import SwiftUI
import Tokens

/// The body of a message the crypto layer could not decrypt.
///
/// Shows the failure and, when the SDK attributed one, the cause it assigned.
/// The view renders `cause` and nothing else: the app never inspects an event
/// or infers crypto state of its own (hard rule 1).
public struct UnableToDecryptView: View {
    let cause: UnableToDecryptCause

    public init(cause: UnableToDecryptCause) {
        self.cause = cause
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Unable to decrypt", systemImage: "lock.trianglebadge.exclamationmark")
                .italic()
                .foregroundStyle(.secondary)

            if let reason = cause.displayText {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The "(edited)" marker under a message the sender replaced.
///
/// With `showHistory`, a click on the mark opens the edit history
/// (MATRIX-209). The button is plain, so the mark keeps its size and the row
/// height does not change.
public struct EditedMarker: View {
    let showHistory: (@MainActor () -> Void)?

    /// - Parameter showHistory: Opens the edit history, or nil for a mark
    ///   that takes no clicks.
    public init(showHistory: (@MainActor () -> Void)? = nil) {
        self.showHistory = showHistory
    }

    public var body: some View {
        if let showHistory {
            Button(action: showHistory) {
                label
            }
            .buttonStyle(.plain)
            .linkPointerStyle()
            .help("Show Edit History")
        } else {
            label
        }
    }

    private var label: some View {
        Text("(edited)")
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        UnableToDecryptView(cause: .unknown)
        UnableToDecryptView(cause: .sentBeforeWeJoined)
        UnableToDecryptView(cause: .withheldBySender)
        EditedMarker()
    }
    .frame(width: 400)
    .padding()
    .background(Color(PlatformColor.controlBackgroundColor))
}
