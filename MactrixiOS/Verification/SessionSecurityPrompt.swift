import Models

/// This session's verification state, without the SDK type, so that the
/// decision below is testable.
enum SessionVerificationStatus: Equatable {
    case unknown
    case verified
    case unverified
}

/// One item in the iOS security banner.
enum SessionSecurityItem: Hashable {
    /// Another device asks to verify this session.
    case incomingRequest(senderID: String)
    /// The account's cross-signing identity was reset elsewhere (S-24).
    case identityReset
    /// This session is not verified. `requested` is true after the app sent a
    /// request to the other devices.
    case unverified(requested: Bool)
    /// No secret storage exists. Setup is destructive if that is wrong.
    case recoverySetup
    /// Secret storage exists, but this device cannot read it.
    case recoveryKeyNeeded
}

enum SessionSecurityPrompt {
    /// Decides which items the banner shows, in display order.
    ///
    /// Same rules as the Mac sidebar (`SessionVerificationStatusView`): an
    /// incoming request hides everything else. If not, the identity-reset
    /// banner, the unverified prompt, and the recovery prompt show together,
    /// because verification and recovery are separate problems (S-07).
    /// `IdentityResetPrompt` and `RecoveryPrompt` keep their own sync gates.
    static func decide(
        incomingRequestSender: String?,
        verification: SessionVerificationStatus?,
        requestedVerification: Bool,
        identityReset: IdentityResetPrompt,
        recovery: RecoveryPrompt
    ) -> [SessionSecurityItem] {
        if let incomingRequestSender {
            return [.incomingRequest(senderID: incomingRequestSender)]
        }

        var items: [SessionSecurityItem] = []
        if identityReset == .identityReset {
            items.append(.identityReset)
        }
        if verification == .unverified {
            items.append(.unverified(requested: requestedVerification))
        }
        switch recovery {
        case .offerSetup:
            items.append(.recoverySetup)
        case .offerKeyEntry:
            items.append(.recoveryKeyNeeded)
        case .none, .healthy:
            break
        }
        return items
    }
}
