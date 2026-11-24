@testable import Core
import Foundation
import Testing

private struct FakeThreadPaginationFailure: Error {}

/// A thread focus as the SDK paginates it (matrix-rust-sdk 5e0a2b8, seen
/// in the app log of 2026-11-24): the panel opens with the newest reply
/// only, the first calls add no event, each later call adds one event,
/// and only the call that brings in the root returns true.
@MainActor
private final class FakeThreadPagination {
    /// The loaded events, oldest first.
    private(set) var loaded: [String]
    /// The events not loaded yet, newest first. The root is last.
    private var older: [String]
    private var emptyCalls: Int
    private let failAtCall: Int?
    private(set) var calls = 0
    private(set) var pauses = 0

    init(replies: Int, emptyCalls: Int = 2, failAtCall: Int? = nil) {
        older = (1 ..< replies).reversed().map { "$reply\($0)" } + ["$root"]
        loaded = ["$reply\(replies)"]
        self.emptyCalls = emptyCalls
        self.failAtCall = failAtCall
    }

    /// `Timeline.paginateBackwards(numEvents:)` on a thread focus.
    func paginateBackwards() throws -> Bool {
        calls += 1
        if calls == failAtCall {
            throw FakeThreadPaginationFailure()
        }
        if emptyCalls > 0 {
            emptyCalls -= 1
            return false
        }
        guard !older.isEmpty else { return true }
        loaded.insert(older.removeFirst(), at: 0)
        return older.isEmpty
    }

    func pause() {
        pauses += 1
    }

    var hasRoot: Bool {
        loaded.first == "$root"
    }
}

/// MATRIX-229: the thread panel loads the whole thread when it opens, with
/// no scroll.
@MainActor
struct ThreadBackfillTests {
    private func fill(_ thread: FakeThreadPagination, callLimit: Int = ThreadBackfill.callLimit) async -> ThreadBackfill.Outcome {
        await ThreadBackfill.run(
            callLimit: callLimit,
            paginateOnce: { _ in try thread.paginateBackwards() },
            pause: { thread.pause() }
        )
    }

    @Test func openingAThreadLoadsEveryReplyAndTheRootWithoutAScroll() async {
        let thread = FakeThreadPagination(replies: 24)

        let outcome = await fill(thread)

        // 2 calls with no event, then 23 older replies and the root.
        #expect(outcome == .reachedStart(calls: 26))
        #expect(thread.hasRoot)
        #expect(thread.loaded.count == 25)
        #expect(thread.calls == 26)
    }

    @Test func callsThatAddNoEventDoNotStopTheFill() async {
        let thread = FakeThreadPagination(replies: 3, emptyCalls: 5)

        let outcome = await fill(thread)

        #expect(outcome == .reachedStart(calls: 8))
        #expect(thread.hasRoot)
    }

    @Test func aThreadWithItsRootLoadedStopsAfterOneCall() async {
        let thread = FakeThreadPagination(replies: 1, emptyCalls: 0)

        let outcome = await fill(thread)

        #expect(outcome == .reachedStart(calls: 1))
        #expect(thread.pauses == 0)
    }

    @Test func theFillPausesBetweenCallsOnly() async {
        let thread = FakeThreadPagination(replies: 4, emptyCalls: 0)

        let outcome = await fill(thread)

        #expect(outcome == .reachedStart(calls: 4))
        #expect(thread.pauses == 3)
    }

    @Test func aLongThreadStopsAtTheCallLimit() async {
        let thread = FakeThreadPagination(replies: 200)

        let outcome = await fill(thread)

        #expect(outcome == .callLimit(calls: ThreadBackfill.callLimit))
        #expect(thread.calls == ThreadBackfill.callLimit)
        #expect(!thread.hasRoot)
    }

    @Test func aFailedCallStopsTheFill() async {
        let thread = FakeThreadPagination(replies: 24, failAtCall: 4)

        let outcome = await fill(thread)

        guard case let .failed(calls, _) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(calls == 4)
        #expect(thread.calls == 4)
    }

    @Test func aCancelledPauseStopsTheFill() async {
        let thread = FakeThreadPagination(replies: 24)

        let outcome = await ThreadBackfill.run(
            paginateOnce: { _ in try thread.paginateBackwards() },
            pause: { throw CancellationError() }
        )

        guard case let .failed(calls, _) = outcome else {
            Issue.record("expected a stop, got \(outcome)")
            return
        }
        #expect(calls == 1)
        #expect(thread.calls == 1)
    }

    @Test func theCallsAreNumberedFromOne() async {
        let thread = FakeThreadPagination(replies: 2, emptyCalls: 1)
        var numbers: [Int] = []

        _ = await ThreadBackfill.run(
            paginateOnce: { call in
                numbers.append(call)
                return try thread.paginateBackwards()
            },
            pause: {}
        )

        #expect(numbers == [1, 2, 3])
    }

    @Test func aZeroCallLimitMakesNoCall() async {
        let thread = FakeThreadPagination(replies: 2)

        let outcome = await fill(thread, callLimit: 0)

        #expect(outcome == .callLimit(calls: 0))
        #expect(thread.calls == 0)
    }
}
