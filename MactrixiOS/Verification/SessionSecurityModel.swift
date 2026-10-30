import Core
import Foundation
import MatrixRustSDK
import Models
import Observation
import OSLog

/// Drives device verification (emoji SAS) and key recovery on iOS.
///
/// The SDK calls are the ones the Mac app makes: `MatrixClient`'s
/// verification helpers, the session verification controller for the SAS
/// answer, and `RecoveryProgress` for recovery. Every action is a no-op when
/// no client is attached.
@MainActor @Observable
final class SessionSecurityModel {
    let appState: AppState
    let recovery = RecoveryProgress()

    /// True after this device asked the other devices to verify it.
    private(set) var requestedVerification = false
    /// The flow ID of the incoming request the user accepted.
    private(set) var acceptedRequestFlowID: String?

    var showingRecoveryKeyEntry = false
    var confirmingRecoverySetup = false

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.davlin.matrixclient.ios", category: "verification")

    init(appState: AppState) {
        self.appState = appState
    }

    private var client: MatrixClient? { appState.matrixClient }

    /// The SDK client. `MatrixClient.reset()` sets it to nil before
    /// `AppState` drops the `MatrixClient`, so it is read as an optional.
    private var sdkClient: ClientProtocol? {
        guard let client, let sdkClient = client.client else { return nil }
        return sdkClient
    }

    // MARK: State

    var items: [SessionSecurityItem] {
        guard let client else { return [] }
        // Same gate as the Mac: account data is only trustworthy after the
        // first sync, which the room list reports as `.running`.
        let hasCompletedInitialSync = client.roomListServiceState == .running
        return SessionSecurityPrompt.decide(
            incomingRequestSender: client.sessionVerificationRequest?.senderProfile.userId,
            verification: client.verificationState.map(Self.status(for:)),
            requestedVerification: requestedVerification,
            identityReset: IdentityResetPrompt.decide(
                hasVerificationViolation: client.hasIdentityViolation,
                wasPreviouslyVerified: client.wasPreviouslyVerified,
                hasCompletedInitialSync: hasCompletedInitialSync
            ),
            recovery: RecoveryPrompt.decide(
                status: client.recoveryState.asModel,
                hasCompletedInitialSync: hasCompletedInitialSync
            )
        )
    }

    static func status(for state: VerificationState) -> SessionVerificationStatus {
        switch state {
        case .unknown: .unknown
        case .verified: .verified
        case .unverified: .unverified
        }
    }

    /// The emoji or decimal data of a running SAS flow, if any.
    var verificationData: Models.SessionVerificationData<MatrixRustSDK.SessionVerificationEmoji>? {
        client?.sessionVerificationData?.asModel
    }

    var isAwaitingAcceptedRequest: Bool {
        guard let request = client?.sessionVerificationRequest else { return false }
        return request.flowId == acceptedRequestFlowID
    }

    var recoveryErrorMessage: String? {
        if case let .failed(message) = recovery.phase {
            message
        } else { nil }
    }

    var recoveryProgressDetail: String? {
        if case let .enabling(detail) = recovery.phase {
            detail
        } else { nil }
    }

    // MARK: Verification

    /// Asks the user's other devices to verify this session.
    func requestVerification() async {
        guard let client else { return }
        do {
            try await client.requestDeviceVerification()
            requestedVerification = true
        } catch {
            Self.logger.error("request device verification failed: \(String(describing: error), privacy: .public)")
        }
    }

    func acceptIncomingRequest() async {
        guard let client, let request = client.sessionVerificationRequest else { return }
        acceptedRequestFlowID = request.flowId
        do {
            try await client.acceptVerificationRequest(request: request)
        } catch {
            Self.logger.error("failed to accept verification request: \(String(describing: error), privacy: .public)")
            acceptedRequestFlowID = nil
            client.sessionVerificationRequest = nil
        }
    }

    func declineIncomingRequest() async {
        guard let client, let request = client.sessionVerificationRequest else { return }
        do {
            try await client.declineVerificationRequest(request: request)
        } catch {
            Self.logger.error("failed to decline verification request: \(String(describing: error), privacy: .public)")
            client.sessionVerificationRequest = nil
        }
    }

    /// The user's answer to "do the emojis match?".
    func answerVerification(match: Bool) async {
        guard let client, let sdkClient else { return }
        do {
            let controller = try await sdkClient.getSessionVerificationController()
            if match {
                try await controller.approveVerification()
            } else {
                try await controller.declineVerification()
            }
        } catch {
            Self.logger.error("failed to answer verification: \(String(describing: error), privacy: .public)")
            client.sessionVerificationData = nil
        }
    }

    // MARK: Recovery

    func enableRecovery() async {
        guard let sdkClient else { return }
        await recovery.enable(using: sdkClient.encryption())
    }

    func recover(with key: String) async {
        guard let sdkClient else { return }
        await recovery.recover(with: key, using: sdkClient.encryption())
        if case .recovered = recovery.phase {
            showingRecoveryKeyEntry = false
        }
    }

    func cancelRecoveryKeyEntry() {
        recovery.dismissError()
        showingRecoveryKeyEntry = false
    }

    // MARK: Session

    /// Signs out and deletes this session's local data. The identity-reset
    /// banner confirms with the user before it calls this.
    func signOut() async {
        try? await appState.reset()
        requestedVerification = false
        acceptedRequestFlowID = nil
    }
}
