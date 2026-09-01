import SwiftUI

/// Banner shown when the account's own cross-signing identity was reset
/// externally (e.g. from Element Web) while this session had the old
/// identity pinned.
///
/// The SDK's `UserIdentity.hasVerificationViolation()` is the detection
/// signal — see `IdentityResetPrompt.decide`.
///
/// Two recovery actions:
///   1. Re-verify against another device — wires to the existing session
///      verification flow.
///   2. Sign out and back in — wires to `AppState.reset()`.
public struct IdentityResetBanner: View {
    let onVerify: () -> Void
    let onSignOut: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(onVerify: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.onVerify = onVerify
        self.onSignOut = onSignOut
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .bold()
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your identity was reset")
                        .bold()
                    Text(
                        "Your account's cross-signing identity was reset from another device. "
                            + "Messages may not be secure until you re-verify."
                    )
                    .lineLimit(9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("Re-verify…", action: onVerify)
                Button("Sign out") { onSignOut() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.2))
        .foregroundStyle(Color.red.mix(with: colorScheme == .light ? .black : .white, by: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
