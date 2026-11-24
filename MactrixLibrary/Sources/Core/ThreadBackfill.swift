import Foundation

/// The fill that loads a whole thread when the thread panel opens
/// (MATRIX-229).
///
/// A thread timeline gets no pagination status from the SDK, so nothing asks
/// for the next batch the way the main timeline's status listener does. One
/// `paginateBackwards` call on a thread focus is one event cache
/// `run_backwards_once` (matrix-rust-sdk 5e0a2b8): it loads one stored chunk
/// of the thread, or makes one `/relations` request. `numEvents` limits only
/// the request. A stored chunk can hold a single reply, and a call can add no
/// row at all, so the fill does not count rows. It calls again until the SDK
/// reports the thread start, a call fails, or the call limit is reached. Past
/// the limit, a scroll near the top asks for the next batch, as before.
@MainActor
enum ThreadBackfill {
    /// The most calls one fill makes: about 50 replies when each call loads
    /// one stored reply, and a bound on the loop if the SDK never reports the
    /// start. A network call can give up to 100 events, so a fill that only
    /// reaches the network stops at about 5000.
    static let callLimit = 50

    /// The pause between two calls. The diff of one call reaches the table
    /// before the next call starts, and a call that returns at once does not
    /// make a tight loop.
    static let pause: Duration = .milliseconds(50)

    /// Why a fill stopped, and after how many calls.
    enum Outcome: Equatable {
        /// The SDK reported the thread start: the root is in.
        case reachedStart(calls: Int)
        /// The fill made `callLimit` calls without the start.
        case callLimit(calls: Int)
        /// A call or a pause threw. `message` is the error's localized
        /// description, for the failure row.
        case failed(calls: Int, message: String)
    }

    /// Runs the fill.
    ///
    /// - Parameters:
    ///   - callLimit: The most calls to make.
    ///   - paginateOnce: One back-pagination call, given its number from 1.
    ///     Returns true when the thread start is in.
    ///   - pause: Waits between two calls. Not called before the first call
    ///     or after the last.
    static func run(
        callLimit: Int = callLimit,
        paginateOnce: (_ call: Int) async throws -> Bool,
        pause: () async throws -> Void
    ) async -> Outcome {
        var calls = 0
        while calls < callLimit {
            do {
                if calls > 0 {
                    try await pause()
                }
                calls += 1
                if try await paginateOnce(calls) {
                    return .reachedStart(calls: calls)
                }
            } catch {
                return .failed(calls: calls, message: error.localizedDescription)
            }
        }
        return .callLimit(calls: calls)
    }
}
