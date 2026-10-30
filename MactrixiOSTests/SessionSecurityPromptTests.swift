import Core
@testable import MactrixiOS
import Models
import XCTest

/// MATRIX-83: which verification and recovery prompts the iOS banner shows.
@MainActor
final class SessionSecurityPromptTests: XCTestCase {
    private func decide(
        sender: String? = nil,
        verification: SessionVerificationStatus? = .verified,
        requested: Bool = false,
        identityReset: IdentityResetPrompt = .none,
        recovery: RecoveryPrompt = .healthy
    ) -> [SessionSecurityItem] {
        SessionSecurityPrompt.decide(
            incomingRequestSender: sender,
            verification: verification,
            requestedVerification: requested,
            identityReset: identityReset,
            recovery: recovery
        )
    }

    func testHealthySessionShowsNothing() {
        XCTAssertEqual(decide(), [])
    }

    func testUnknownOrMissingVerificationShowsNothing() {
        XCTAssertEqual(decide(verification: .unknown), [])
        XCTAssertEqual(decide(verification: nil), [])
    }

    func testUnverifiedSessionOffersVerification() {
        XCTAssertEqual(decide(verification: .unverified), [.unverified(requested: false)])
        XCTAssertEqual(decide(verification: .unverified, requested: true), [.unverified(requested: true)])
    }

    func testIncomingRequestHidesEverythingElse() {
        let items = decide(
            sender: "@patrick:davlin.io",
            verification: .unverified,
            identityReset: .identityReset,
            recovery: .offerKeyEntry
        )

        XCTAssertEqual(items, [.incomingRequest(senderID: "@patrick:davlin.io")])
    }

    func testVerificationAndRecoveryShowTogether() {
        // S-07: a verified session can still have no route to its history,
        // so the two prompts are separate items.
        XCTAssertEqual(
            decide(verification: .unverified, recovery: .offerKeyEntry),
            [.unverified(requested: false), .recoveryKeyNeeded]
        )
        XCTAssertEqual(decide(recovery: .offerSetup), [.recoverySetup])
    }

    func testIdentityResetComesFirst() {
        XCTAssertEqual(
            decide(verification: .unverified, identityReset: .identityReset),
            [.identityReset, .unverified(requested: false)]
        )
    }

    func testRecoveryBeforeTheFirstSyncShowsNothing() {
        // The sync gate lives in `RecoveryPrompt.decide`. Run the real
        // decision to prove the banner does not bypass it (2026-08-30).
        let recovery = RecoveryPrompt.decide(status: .disabled, hasCompletedInitialSync: false)

        XCTAssertEqual(decide(recovery: recovery), [])
    }

    func testSecurityModelWithoutAClientShowsNothingAndIgnoresActions() async {
        let model = SessionSecurityModel(appState: AppState())

        XCTAssertEqual(model.items, [])
        XCTAssertNil(model.verificationData)
        XCTAssertFalse(model.isAwaitingAcceptedRequest)

        await model.requestVerification()
        await model.acceptIncomingRequest()
        await model.answerVerification(match: true)
        await model.enableRecovery()

        XCTAssertFalse(model.requestedVerification)
        XCTAssertEqual(model.recovery.phase, .idle)
    }

    func testCancellingKeyEntryClosesTheSheet() {
        let model = SessionSecurityModel(appState: AppState())
        model.showingRecoveryKeyEntry = true

        model.cancelRecoveryKeyEntry()

        XCTAssertFalse(model.showingRecoveryKeyEntry)
        XCTAssertNil(model.recoveryErrorMessage)
    }
}
