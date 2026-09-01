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
///   2. Sign out and back in — wires to `AppState.reset()`. Destructive
///      (the local store and keychain session are deleted), so it asks
///      for confirmation first, per the S-25 post-incident rule.
public struct IdentityResetBanner: View {
    let onVerify: () -> Void
    let onSignOut: () -> Void

    @State private var confirmingSignOut = false
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
                    .buttonStyle(.borderedProminent)
                Button("Sign out", role: .destructive) {
                    confirmingSignOut = true
                }
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.2))
        .foregroundStyle(Color.red.mix(with: colorScheme == .light ? .black : .white, by: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Signing out is irreversible from this session's point of view —
        // `AppState.reset()` logs out and deletes the local store — so the
        // user gets the last word, mirroring the recovery-setup confirmation.
        .alert("Sign out?", isPresented: $confirmingSignOut) {
            Button("Sign out", role: .destructive) {
                onSignOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes this session's data from this Mac. You will need to sign in again.")
        }
    }
}
