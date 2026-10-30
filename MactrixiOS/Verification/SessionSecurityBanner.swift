import Core
import SwiftUI
import UI

/// The verification and recovery prompts, as a stack of opaque cards.
///
/// The cards are content, not navigation chrome, so they use solid tinted
/// fills and no glass (hard rule 2). The view is empty when nothing needs
/// action.
struct SessionSecurityBanner: View {
    let model: SessionSecurityModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let items = model.items
        if !items.isEmpty {
            VStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    row(for: item)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func row(for item: SessionSecurityItem) -> some View {
        switch item {
        case let .incomingRequest(senderID):
            incomingRequestCard(senderID: senderID)
        case .identityReset:
            IdentityResetBanner(
                onVerify: { Task { await model.requestVerification() } },
                onSignOut: { Task { await model.signOut() } }
            )
        case let .unverified(requested):
            unverifiedCard(requested: requested)
        case .recoverySetup:
            recoveryCard(
                icon: "exclamationmark.shield",
                title: "Recovery is not set up",
                detail: "Without it, your encrypted history cannot be restored if you lose this device.",
                button: "Set Up Recovery…"
            ) { model.confirmingRecoverySetup = true }
        case .recoveryKeyNeeded:
            recoveryCard(
                icon: "key.horizontal",
                title: "Recovery key needed",
                detail: "Your account has a backup this device cannot read yet. Enter your recovery key to unlock it.",
                button: "Enter Recovery Key…"
            ) { model.showingRecoveryKeyEntry = true }
        }
    }

    private func incomingRequestCard(senderID: String) -> some View {
        card(tint: .green) {
            Label("Verification request from \(senderID)", systemImage: "person.badge.key")
                .bold()
            if model.isAwaitingAcceptedRequest {
                HStack {
                    ProgressView()
                    Text("Waiting for the other device…")
                }
            } else {
                HStack {
                    Button("Start Verification") { Task { await model.acceptIncomingRequest() } }
                        .buttonStyle(.borderedProminent)
                    Button("Decline") { Task { await model.declineIncomingRequest() } }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func unverifiedCard(requested: Bool) -> some View {
        card(tint: .red) {
            Label("This session is unverified.", systemImage: "exclamationmark.shield")
                .bold()
            Text("Verify it from another device to decrypt all messages and for better security.")
                .fixedSize(horizontal: false, vertical: true)
            if requested {
                HStack {
                    ProgressView()
                    Text("Accept the request on another device.")
                }
            }
            Button(requested ? "Try Again" : "Verify Session…") {
                Task { await model.requestVerification() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("verifySessionButton")
        }
    }

    private func recoveryCard(
        icon: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        button: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        card(tint: .orange) {
            Label(title, systemImage: icon)
                .bold()
            Text(detail)
                .fixedSize(horizontal: false, vertical: true)
            if let progress = model.recoveryProgressDetail {
                HStack {
                    ProgressView()
                    Text(progress).foregroundStyle(.secondary)
                }
            } else if let error = model.recoveryErrorMessage, !model.showingRecoveryKeyEntry {
                Text(error).foregroundStyle(.red).lineLimit(3)
            }
            Button(button, action: action)
                .buttonStyle(.bordered)
                .disabled(model.recovery.isBusy)
        }
    }

    private func card(tint: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(tint.mix(with: colorScheme == .light ? .black : .white, by: 0.5))
    }
}
