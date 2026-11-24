@testable import Core
import Foundation
import MatrixRustSDK
import Testing

/// Records the values that `AsyncSDKListener.deliver(to:)` applies.
@MainActor
private final class AppliedValues<Value> {
    private(set) var values: [Value] = []
    private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    func append(_ value: Value) {
        values.append(value)
        if let waiter, values.count >= waiter.count {
            self.waiter = nil
            waiter.continuation.resume()
        }
    }

    /// Returns when `count` values were applied.
    func wait(forCount count: Int) async {
        guard values.count < count else { return }
        await withCheckedContinuation { continuation in
            waiter = (count, continuation)
        }
    }
}

/// MATRIX-237: the SDK listener values reach the main actor in the order the
/// SDK sent them, so the newest value wins.
///
/// The app used one `Task { @MainActor in ... }` for each callback. Those
/// tasks have no order. These tests send values from an SDK-like background
/// thread through the listener's FFI method, as the SDK does.
@MainActor
struct SyncStateDeliveryTests {
    /// The SDK sends `idle` when the listener attaches (`next_now()` in
    /// `SyncService::state`), then `running` from `start()`. A handler that
    /// suspends on the first value must not let the second land first.
    ///
    /// With one task for each callback, the `running` task finishes while
    /// the `idle` task sleeps, and `idle` lands last: the sidebar then shows
    /// "Connecting…" while sync runs.
    @Test func aSuspendingHandlerDoesNotLetALaterStateOvertake() async {
        let listener = AsyncSDKListener<SyncServiceState>()
        let applied = AppliedValues<SyncServiceState>()
        let task = listener.deliver { state in
            if state == .idle {
                try? await Task.sleep(for: .milliseconds(50))
            }
            applied.append(state)
        }
        defer { task.cancel() }

        await Task.detached {
            listener.onUpdate(state: .idle)
            listener.onUpdate(state: .running)
        }.value
        await applied.wait(forCount: 2)

        #expect(applied.values == [.idle, .running])
    }

    /// Many states from a background thread arrive complete and in order.
    @Test func statesArriveInTheOrderTheSDKSentThem() async {
        let cycle: [SyncServiceState] = [.idle, .running, .offline, .running, .error, .idle, .running, .terminated]
        let sent = Array(repeating: cycle, count: 50).flatMap(\.self)
        let listener = AsyncSDKListener<SyncServiceState>()
        let applied = AppliedValues<SyncServiceState>()
        let task = listener.deliver { applied.append($0) }
        defer { task.cancel() }

        await Task.detached {
            for state in sent {
                listener.onUpdate(state: state)
            }
        }.value
        await applied.wait(forCount: sent.count)

        #expect(applied.values == sent)
        #expect(applied.values.last == .terminated)
    }

    /// The verification callbacks keep their order: a `finish` after the
    /// SAS stage clears the sheet, and nothing sets it again.
    @Test func sessionVerificationCallbacksArriveInOrder() async {
        let listener = AsyncSDKListener<SessionVerificationEvent>()
        let applied = AppliedValues<String>()
        let task = listener.deliver { event in
            let label = switch event {
            case .receivedRequest: "request"
            case .acceptedRequest: "accepted"
            case .startedSas: "sas"
            case .receivedData: "data"
            case .failed: "failed"
            case .cancelled: "cancelled"
            case .finished: "finished"
            }
            applied.append(label)
        }
        defer { task.cancel() }

        await Task.detached {
            listener.didAcceptVerificationRequest()
            listener.didStartSasVerification()
            listener.didCancel()
            listener.didFail()
            listener.didFinish()
        }.value
        await applied.wait(forCount: 5)

        #expect(applied.values == ["accepted", "sas", "cancelled", "failed", "finished"])
    }

    /// The other state listeners use the same stream.
    @Test func roomListStatesArriveInOrder() async {
        let sent: [RoomListServiceState] = [.initial, .settingUp, .running, .recovering, .running]
        let listener = AsyncSDKListener<RoomListServiceState>()
        let applied = AppliedValues<RoomListServiceState>()
        let task = listener.deliver { state in
            if state == .settingUp {
                try? await Task.sleep(for: .milliseconds(20))
            }
            applied.append(state)
        }
        defer { task.cancel() }

        await Task.detached {
            for state in sent {
                listener.onUpdate(state: state)
            }
        }.value
        await applied.wait(forCount: sent.count)

        #expect(applied.values == sent)
    }
}

/// MATRIX-237: the sidebar's sync line.
struct SyncStatusLineTests {
    /// A new service is `idle` until `start()` sets it `running`.
    @Test func idleBeforeTheFirstRunningIsConnecting() {
        let line = SyncStatusLine(state: .idle, hasRun: false, startFailed: false)
        #expect(line == .connecting)
        #expect(!line.canRestart)
    }

    /// `stop()` sets a running service `idle` again. That is not "Connecting…".
    @Test func idleAfterRunningIsStopped() {
        let line = SyncStatusLine(state: .idle, hasRun: true, startFailed: false)
        #expect(line == .stopped)
        #expect(line.canRestart)
    }

    @Test(arguments: [false, true])
    func runningHidesTheLine(hasRun: Bool) {
        #expect(SyncStatusLine(state: .running, hasRun: hasRun, startFailed: false) == .hidden)
    }

    @Test(arguments: [false, true])
    func offlineShowsOffline(hasRun: Bool) {
        let line = SyncStatusLine(state: .offline, hasRun: hasRun, startFailed: false)
        #expect(line == .offline)
        #expect(line.canRestart)
    }

    @Test(arguments: [false, true])
    func errorShowsSyncError(hasRun: Bool) {
        let line = SyncStatusLine(state: .error, hasRun: hasRun, startFailed: false)
        #expect(line == .error)
        #expect(line.canRestart)
    }

    @Test(arguments: [false, true])
    func terminatedShowsSyncStopped(hasRun: Bool) {
        let line = SyncStatusLine(state: .terminated, hasRun: hasRun, startFailed: false)
        #expect(line == .stopped)
        #expect(line.canRestart)
    }

    /// `startSync()` threw after the state listener attached: the service is
    /// `idle` and never starts. The line offers a restart.
    @Test(arguments: [SyncServiceState.idle, .terminated])
    func aFailedStartIsASyncError(state: SyncServiceState) {
        let line = SyncStatusLine(state: state, hasRun: false, startFailed: true)
        #expect(line == .error)
        #expect(line.canRestart)
    }

    @Test func noClientIsSignedOut() {
        let line = SyncStatusLine(state: nil, hasRun: false, startFailed: false)
        #expect(line == .signedOut)
        #expect(!line.canRestart)
    }
}
