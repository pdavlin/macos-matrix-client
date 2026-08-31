/// Mirror of the SDK's `RecoveryState`.
///
/// Mirrored rather than imported for the same reason as `EncryptionState`:
/// this package does not link matrix-rust-components-swift, and adding it
/// would declare the SDK version in a second place where it could drift from
/// the exact pin the Xcode project holds (CLAUDE.md rule 6).
public enum RecoveryStatus: Equatable, Sendable {
    /// Not yet determined.
    case unknown
    /// Secret storage exists and this device can read it.
    case enabled
    /// No secret storage exists on the server.
    case disabled
    /// Secret storage exists but this device is missing secrets from it.
    case incomplete
}

/// Which recovery prompt, if any, the user should be shown.
public enum RecoveryPrompt: Equatable, Sendable {
    case none
    /// Recovery is set up. Informational only.
    case healthy
    /// No secret storage exists. Destructive if the state is wrong, because
    /// enabling replaces any existing secret storage.
    case offerSetup
    /// Secret storage exists but this device cannot read it.
    case offerKeyEntry

    /// Decides the prompt.
    ///
    /// - Parameters:
    ///   - status: the SDK's recovery state, mirrored.
    ///   - hasCompletedInitialSync: whether the room list reports `.running`.
    ///
    /// `RecoveryStatus` is derived from account data held in the local store.
    /// A freshly logged-in session has an empty store, so the SDK reports a
    /// confident `disabled` — not `unknown` — for an account that does have
    /// recovery. On 2026-08-30 the app believed that, offered "Set up
    /// recovery" to a session that already had a key, and enabling replaced
    /// it. Hence the sync gate on the two states derived from account data.
    public static func decide(status: RecoveryStatus, hasCompletedInitialSync: Bool) -> RecoveryPrompt {
        switch status {
        case .unknown:
            .none
        case .enabled:
            // Needs no gate: the SDK cannot report `enabled` from an empty
            // store, since saying so requires having read a default key.
            .healthy
        case .disabled:
            hasCompletedInitialSync ? .offerSetup : .none
        case .incomplete:
            hasCompletedInitialSync ? .offerKeyEntry : .none
        }
    }
}
