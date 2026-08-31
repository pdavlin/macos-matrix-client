import Foundation
import MatrixRustSDK
import OSLog
import SwiftUI

/// Drives the two recovery operations and holds their transient state.
///
/// Recovery is the account's route back to its own history. Without secret
/// storage, a key backup on the server cannot be read by any device that does
/// not already hold the keys locally — see the S-25 investigation and the
/// `RecoveryState` semantics recorded in contract §11.
///
/// Two operations, chosen by `RecoveryState`:
///   - `.disabled` — no secret storage exists. `enable()` creates it and
///     returns a recovery key **once**.
///   - `.incomplete` — secret storage exists but this device cannot read it.
///     `recover(with:)` unlocks it with that key.
///
/// This type deliberately does not persist the recovery key anywhere. It is
/// held in memory only, for as long as the sheet showing it is open.
@MainActor @Observable
final class RecoveryProgress {
    enum Phase: Equatable {
        case idle
        /// Enabling. `detail` is a human-readable stage from the SDK.
        case enabling(detail: String)
        /// Enabling finished. The key is shown once and never stored.
        case showingKey(String)
        case recovering
        case recovered
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// True while an operation is in flight, so views can disable their entry
    /// points rather than allowing a second concurrent attempt.
    var isBusy: Bool {
        switch phase {
        case .enabling, .recovering: true
        case .idle, .showingKey, .recovered, .failed: false
        }
    }

    /// The recovery key, if one is currently being shown.
    ///
    /// Read by the display sheet and discarded with `acknowledgeKey()`. It is
    /// never logged and never written to disk: `enableRecovery` returns it
    /// exactly once, and only `resetRecoveryKey` can issue another — which
    /// invalidates the one the user may already have saved.
    var pendingRecoveryKey: String? {
        if case let .showingKey(key) = phase {
            key
        } else { nil }
    }

    /// Creates secret storage and a new recovery key.
    ///
    /// `waitForBackupsToUpload` is true so that "done" means the backup is
    /// actually populated. Reporting success before the room keys have
    /// uploaded would promise a recovery that does not yet exist.
    func enable(using encryption: Encryption) async {
        guard !isBusy else { return }
        phase = .enabling(detail: "Starting…")

        let listener = EnableRecoveryProgressRelay { [weak self] detail in
            guard let self else { return }
            if case .enabling = phase { phase = .enabling(detail: detail) }
        }

        do {
            let key = try await encryption.enableRecovery(
                waitForBackupsToUpload: true,
                passphrase: nil,
                progressListener: listener
            )
            Logger.matrixClient.info("recovery enabled; key returned to the user once")
            phase = .showingKey(key)
        } catch {
            // The key never appears in an error path, so this is safe to log.
            Logger.matrixClient.error("enableRecovery failed: \(error)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Unlocks existing secret storage with a recovery key.
    func recover(with recoveryKey: String, using encryption: Encryption) async {
        guard !isBusy else { return }
        let trimmed = recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        phase = .recovering
        do {
            try await encryption.recover(recoveryKey: trimmed)
            Logger.matrixClient.info("recovery key accepted; secret storage unlocked")
            phase = .recovered
        } catch {
            // Never interpolate the key here. A wrong key is a user error, not
            // a secret worth recording, but the right key would be.
            Logger.matrixClient.error("recover failed: \(error)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Drops the key from memory once the user confirms they have saved it.
    func acknowledgeKey() {
        phase = .idle
    }

    func dismissError() {
        if case .failed = phase { phase = .idle }
    }
}

/// Bridges the SDK's progress callbacks onto the main actor as display text.
///
/// A separate type because `EnableRecoveryProgressListener` is `Sendable` and
/// called from the SDK's own threads, while `RecoveryProgress` is main-actor
/// isolated.
private final class EnableRecoveryProgressRelay: EnableRecoveryProgressListener {
    private let onDetail: @MainActor (String) -> Void

    init(onDetail: @escaping @MainActor (String) -> Void) {
        self.onDetail = onDetail
    }

    func onUpdate(status: EnableRecoveryProgress) {
        // `done` carries the recovery key. It is deliberately not forwarded:
        // the key reaches the caller as `enableRecovery`'s return value, and
        // routing a secret through display text invites it into a log.
        let detail: String? = switch status {
        case .starting:
            "Starting…"
        case .creatingBackup:
            "Creating key backup…"
        case .creatingRecoveryKey:
            "Creating recovery key…"
        case let .backingUp(backedUpCount, totalCount):
            "Backing up keys (\(backedUpCount) of \(totalCount))…"
        case .roomKeyUploadError:
            "Retrying key upload…"
        case .done:
            nil
        }

        guard let detail else { return }
        Task { @MainActor [onDetail] in onDetail(detail) }
    }
}
