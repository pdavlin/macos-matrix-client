import Core
import Foundation
import Observation
import OSLog
import UIKit
import Utils

/// Owns the iOS session: keychain restore at launch, attaching a client after
/// sign-in, starting sync, and teardown after an auth error.
///
/// Signed-in state is read from `AppState.matrixClient`, not stored here. So
/// any `appState.reset()` (sign out from settings, or the identity-reset
/// banner) returns the app to the sign-in screen with no extra wiring.
///
/// This is the only place on iOS that calls `MatrixClient.startSync()` and
/// `MatrixClient.stopSync()`.
///
/// MATRIX-242: sync stops when every scene is in the background, and starts
/// again when the first scene becomes active (`SceneSyncLifecycle`). Each
/// start and stop runs after the one before it, so the SDK gets them in the
/// order the scenes changed.
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
    @ObservationIgnored private let stopSync: @MainActor (MatrixClient) async -> Void
    @ObservationIgnored private let registerForPush: @MainActor (MatrixClient) async -> Void

    /// MATRIX-242: the phases of the scenes.
    @ObservationIgnored private var scenes = SceneSyncLifecycle()
    /// MATRIX-242: the last sync start or stop. The next one waits for it.
    @ObservationIgnored private var lastSyncStep: Task<Void, Never>?

    private static let subsystem = Bundle.main.bundleIdentifier ?? "io.davlin.matrixclient.ios"
    private static let logger = Logger(subsystem: subsystem, category: "session")
    /// MATRIX-242: the sync lifecycle logs in the category of Core's sync logs.
    private static let syncLogger = Logger(subsystem: subsystem, category: "matrix-client")

    /// MATRIX-242: how long the background task stays after the SDK stop
    /// returns. The SDK can still write to the store for a short time: the
    /// lease of the cross-process lock ends at the next renewal (50 ms in
    /// the pinned SDK), and a sync response that the SDK received before the
    /// stop is handled to its end.
    private static let settleAfterStop = Duration.milliseconds(500)

    /// - Parameters:
    ///   - restore: loads the saved session. The default reads the keychain
    ///     through `MatrixClient.attemptRestore`, the same call the Mac app uses.
    ///   - startSync: starts the sync loop of a new client, or restarts it.
    ///   - stopSync: stops the sync loop before iOS suspends the app.
    ///   - registerForPush: asks for notification permission and registers the
    ///     APNs pusher (MATRIX-89). It does not start sync.
    init(
        appState: AppState,
        restore: @escaping @MainActor () async throws -> MatrixClient? = { try await MatrixClient.attemptRestore() },
        startSync: @escaping @MainActor (MatrixClient) async throws -> Void = { try await $0.startSync() },
        stopSync: @escaping @MainActor (MatrixClient) async -> Void = { await $0.stopSync() },
        registerForPush: @escaping @MainActor (MatrixClient) async -> Void = { await PushRegistration.shared.sessionDidStart($0) }
    ) {
        self.appState = appState
        self.restore = restore
        self.startSync = startSync
        self.stopSync = stopSync
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
    ///
    /// MATRIX-242: while every scene is in the background, sync does not
    /// start here. It starts when a scene becomes active.
    func attach(_ client: MatrixClient) async {
        appState.matrixClient = client
        if scenes.allowsSync {
            await enqueueSyncStep { await self.start(client) }.value
        } else {
            Self.syncLogger.info("sync lifecycle: start waits for the foreground")
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

    /// MATRIX-242: records a change of one scene, and stops or starts sync
    /// when the change asks for it. `SceneSyncObserver` calls this.
    func scene(_ scene: String, did change: SceneSyncLifecycle.Change) {
        let action = scenes.scene(scene, did: change)
        guard let action, let client = appState.matrixClient else { return }
        switch action {
        case .stopForBackground:
            stopForBackground(client)
        case .startForForeground:
            Self.syncLogger.info("sync lifecycle: start for foreground")
            enqueueSyncStep { await self.start(client) }
        }
    }

    /// MATRIX-242: the Retry button of the chat list's sync line. The
    /// MATRIX-237 restart path, as the Mac sidebar's "Restart sync".
    func retrySync() async {
        guard let client = appState.matrixClient else { return }
        Self.syncLogger.info("sync lifecycle: retry")
        await enqueueSyncStep { await self.start(client) }.value
    }

    /// Stops sync inside a UIKit background task, so iOS lets the stop end
    /// before it suspends the app.
    private func stopForBackground(_ client: MatrixClient) {
        Self.syncLogger.info("sync lifecycle: stop for background")
        let backgroundTask = SyncBackgroundTask(name: "Stop sync") {
            Self.syncLogger.error("sync lifecycle: the background time ended before the stop")
        }
        let stop = enqueueSyncStep {
            guard self.isCurrent(client) else { return }
            await self.stopSync(client)
            Self.syncLogger.info("sync lifecycle: stopped for background")
        }
        // Not a sync step: a start for the foreground does not wait for it.
        Task {
            await stop.value
            try? await Task.sleep(for: Self.settleAfterStop)
            backgroundTask.end()
        }
    }

    private func start(_ client: MatrixClient) async {
        guard isCurrent(client) else { return }
        do {
            try await startSync(client)
        } catch {
            // The sync line shows "Sync error" with Retry (MATRIX-242).
            // Same handling as the Mac `MainView`.
            Self.logger.error("failed to start sync: \(String(describing: error), privacy: .public)")
        }
    }

    /// Whether `client` is still the session. A step that waited can find
    /// it signed out: `MatrixClient.reset()` makes its SDK client nil.
    private func isCurrent(_ client: MatrixClient) -> Bool {
        appState.matrixClient === client && client.client != nil && !client.authenticationFailed
    }

    /// Runs `step` after the last sync step ends.
    @discardableResult
    private func enqueueSyncStep(_ step: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = lastSyncStep
        let task = Task {
            await previous?.value
            await step()
        }
        lastSyncStep = task
        return task
    }
}

/// MATRIX-242: a UIKit background task. iOS lets the app run until `end()`,
/// or until the background time ends.
@MainActor
private final class SyncBackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    /// - Parameter onExpiry: called when the background time ends before
    ///   `end()`. The task ends after it.
    init(name: String, onExpiry: @escaping @MainActor () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated {
                onExpiry()
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
