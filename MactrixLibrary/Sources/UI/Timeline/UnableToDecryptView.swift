import Models
import SwiftUI

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
/// Display only. Edit authoring is out of scope, so nothing here is
/// interactive.
public struct EditedMarker: View {
    public init() {}

    public var body: some View {
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
    .background(Color(NSColor.controlBackgroundColor))
}
