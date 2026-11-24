import MatrixRustSDK

/// The sync line at the top of the sidebar, from the SDK sync state.
///
/// MATRIX-237: the SDK reports `idle` in two cases. A new sync service is
/// `idle` until `start()` sets it `running`, and a service that `stop()`
/// paused is `idle` again. Only the first case is "Connecting…". After the
/// first `running`, `idle` means that sync stopped.
public enum SyncStatusLine: Equatable, Sendable {
    /// Sync runs. The sidebar shows no line.
    case hidden
    /// The sync service did not report `running` yet.
    case connecting
    case offline
    case stopped
    case error
    case signedOut

    /// - Parameters:
    ///   - state: the last state the SDK sent, or nil when no client is
    ///     signed in.
    ///   - hasRun: whether this client's sync service sent `running` before.
    ///   - startFailed: whether the last `startSync()` threw.
    public init(state: SyncServiceState?, hasRun: Bool, startFailed: Bool) {
        switch state {
        case nil:
            self = .signedOut
        case .running:
            self = .hidden
        case .idle:
            if startFailed {
                self = .error
            } else {
                self = hasRun ? .stopped : .connecting
            }
        case .terminated:
            self = startFailed ? .error : .stopped
        case .error:
            self = .error
        case .offline:
            self = .offline
        }
    }

    /// Whether the line has a "Restart sync" button.
    public var canRestart: Bool {
        switch self {
        case .offline, .stopped, .error: true
        case .hidden, .connecting, .signedOut: false
        }
    }
}
