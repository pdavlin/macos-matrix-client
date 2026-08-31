@testable import Models
import Testing

/// Covers the rule that decides which recovery prompt appears.
///
/// This exists because the rule got it wrong in a way that destroyed a live
/// recovery key on 2026-08-30. A freshly logged-in session reports `disabled`
/// until its first sync lands, the app offered "Set up recovery" to an account
/// that already had one, and enabling replaced it.
///
/// The wiring to a real session cannot be exercised in a unit test. The
/// decision can, and the decision is where the damage happened.
struct RecoveryPromptTests {
    /// The case that caused the incident.
    @Test
    func disabledBeforeSyncOffersNothing() {
        #expect(RecoveryPrompt.decide(status: .disabled, hasCompletedInitialSync: false) == RecoveryPrompt.none)
    }

    @Test
    func disabledAfterSyncOffersSetup() {
        #expect(RecoveryPrompt.decide(status: .disabled, hasCompletedInitialSync: true) == .offerSetup)
    }

    @Test
    func incompleteRequiresSyncBeforeOfferingKeyEntry() {
        #expect(RecoveryPrompt.decide(status: .incomplete, hasCompletedInitialSync: false) == RecoveryPrompt.none)
        #expect(RecoveryPrompt.decide(status: .incomplete, hasCompletedInitialSync: true) == .offerKeyEntry)
    }

    /// Needs no sync gate: the SDK cannot report `enabled` from an empty store,
    /// because saying so requires having read a default key.
    @Test
    func enabledIsTrustedWithoutTheSyncGate() {
        #expect(RecoveryPrompt.decide(status: .enabled, hasCompletedInitialSync: false) == .healthy)
        #expect(RecoveryPrompt.decide(status: .enabled, hasCompletedInitialSync: true) == .healthy)
    }

    @Test
    func unknownIsNeverActionable() {
        #expect(RecoveryPrompt.decide(status: .unknown, hasCompletedInitialSync: false) == RecoveryPrompt.none)
        #expect(RecoveryPrompt.decide(status: .unknown, hasCompletedInitialSync: true) == RecoveryPrompt.none)
    }

    /// Setup is the only destructive prompt, so state it as an invariant over
    /// every combination rather than trusting the cases above to stay complete.
    @Test
    func setupIsReachableOnlyFromASyncedDisabledState() {
        let statuses: [RecoveryStatus] = [.unknown, .enabled, .disabled, .incomplete]
        for status in statuses {
            for synced in [true, false] {
                let prompt = RecoveryPrompt.decide(status: status, hasCompletedInitialSync: synced)
                guard prompt == .offerSetup else { continue }
                #expect(status == .disabled)
                #expect(synced)
            }
        }
    }
}
