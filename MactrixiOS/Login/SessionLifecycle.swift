import Core
import Foundation
import Observation
import OSLog

/// Owns the iOS session: keychain restore at launch, attaching a client after
/// sign-in, starting sync, and teardown after an auth error.
///
/// Signed-in state is read from `AppState.matrixClient`, not stored here. So
/// any `appState.reset()` (sign out from settings, or the identity-reset
/// banner) returns the app to the sign-in screen with no extra wiring.
///
/// This is the only place on iOS that calls `MatrixClient.startSync()`.
@MainActor @Observable
final class SessionLifecycle {
    enum Phase: Equatable {
        /// The keychain restore has not finished.
        case restoring
        case signedOut
        case signedIn
    }

    let appState: AppState

    private(set) var hasFinishedRestore = false

    @ObservationIgnored private let restore: @MainActor () async throws -> MatrixClient?
    @ObservationIgnored private let startSync: @MainActor (MatrixClient) async throws -> Void
    @ObservationIgnored private let registerForPush: @MainActor (MatrixClient) async -> Void

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.davlin.matrixclient.ios", category: "session")

    /// - Parameters:
    ///   - restore: loads the saved session. The default reads the keychain
    ///     through `MatrixClient.attemptRestore`, the same call the Mac app uses.
    ///   - startSync: starts the sync loop of a new client.
    ///   - registerForPush: asks for notification permission and registers the
    ///     APNs pusher (MATRIX-89). It does not start sync.
    init(
        appState: AppState,
        restore: @escaping @MainActor () async throws -> MatrixClient? = { try await MatrixClient.attemptRestore() },
        startSync: @escaping @MainActor (MatrixClient) async throws -> Void = { try await $0.startSync() },
        registerForPush: @escaping @MainActor (MatrixClient) async -> Void = { await PushRegistration.shared.sessionDidStart($0) }
    ) {
        self.appState = appState
        self.restore = restore
        self.startSync = startSync
        self.registerForPush = registerForPush
    }

    var phase: Phase {
        if appState.matrixClient != nil { return .signedIn }
        return hasFinishedRestore ? .signedOut : .restoring
    }

    /// Restores the saved session once per launch. A failed restore shows the
    /// sign-in screen. The keychain item is kept, as on the Mac.
    func restoreOnLaunch() async {
        guard !hasFinishedRestore else { return }
        defer { hasFinishedRestore = true }
        guard appState.matrixClient == nil else { return }

        do {
            if let client = try await restore() {
                await attach(client)
            }
        } catch {
            Self.logger.error("failed to restore session: \(String(describing: error), privacy: .public)")
        }
    }

    /// Makes a client the app's session, starts its sync loop, and registers
    /// for push. The push registration does not block: it can wait on the
    /// permission prompt.
    func attach(_ client: MatrixClient) async {
        appState.matrixClient = client
        do {
            try await startSync(client)
        } catch {
            // The sync state stays `.terminated` or `.error`, which the UI can
            // show and retry. Same handling as the Mac `MainView`.
            Self.logger.error("failed to start sync: \(String(describing: error), privacy: .public)")
        }
        Task { await registerForPush(client) }
    }

    /// Call when `MatrixClient.authenticationFailed` becomes true. A full
    /// reset, not only dropping the reference: otherwise the stale keychain
    /// session repeats the auth error at the next launch (MATRIX-48).
    func handleAuthenticationFailure() async {
        Self.logger.info("auth failed: tearing down the session")
        try? await appState.reset()
    }
}
