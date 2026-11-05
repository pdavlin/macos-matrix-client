import Foundation
import MatrixRustSDK
import Models
import OSLog

@MainActor @Observable
public final class AppState {
    public var matrixClient: MatrixClient?

    /// Whether the saved-session restore at launch finished, with or
    /// without a session (MATRIX-116). A room window restored on relaunch
    /// waits for this before it decides the user is signed out.
    public private(set) var hasFinishedSessionRestore = false

    /// The one restore at launch. Every window that asks shares it.
    @ObservationIgnored private var sessionRestoreTask: Task<Void, Never>?

    public init() {}

    /// Restores the saved session and starts sync, once per app run.
    ///
    /// The main window and every restored room window call this when they
    /// appear (MATRIX-116). The first call does the work and the others wait
    /// for it, so there is never more than one client or one sync service.
    /// A relaunch that restores only room windows still gets a session.
    ///
    /// After it returns, `matrixClient` is the restored client, or `nil` when
    /// no session is saved or the restore failed. A sync start failure is
    /// logged only: the sidebar's "Restart sync" button retries it
    /// (MATRIX-56).
    public func restoreSavedSession() async {
        if let sessionRestoreTask {
            await sessionRestoreTask.value
            return
        }
        let task = Task { await performSessionRestore() }
        sessionRestoreTask = task
        await task.value
    }

    private func performSessionRestore() async {
        defer { hasFinishedSessionRestore = true }
        guard matrixClient == nil else { return }

        do {
            matrixClient = try await MatrixClient.attemptRestore()
        } catch {
            Logger.viewCycle.error("Failed to restore matrix session: \(error)")
            return
        }

        guard let matrixClient else { return }
        do {
            try await matrixClient.startSync()
        } catch {
            Logger.viewCycle.error("Failed to start sync: \(String(describing: error), privacy: .public)")
        }
    }

    public func reset() async throws {
        do {
            try await matrixClient?.reset()
        } catch {
            Logger.viewCycle.error("Failed to reset matrix client: \(error)")
        }
        matrixClient = nil
    }
}
