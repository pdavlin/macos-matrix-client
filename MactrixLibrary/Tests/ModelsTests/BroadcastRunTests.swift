import Foundation
@testable import Models
import Testing

/// MATRIX-168: the broadcast run, with an injected send and pause. No test
/// here uses a clock or a network.
@MainActor
struct BroadcastRunTests {
    private struct SendFailure: LocalizedError {
        var errorDescription: String? {
            "The room refused\nthe message."
        }
    }

    /// Records the sends and the pauses of a run.
    @MainActor
    private final class Recorder {
        var sentRoomIds: [String] = []
        var sentTexts: Set<String> = []
        var pauseCount = 0
        /// The rooms whose send throws. A room leaves the set when a test
        /// removes it.
        var failingRoomIds: Set<String> = []
        /// Runs before each send returns, with the room ID.
        var onSend: (String) -> Void = { _ in }
        /// Runs in each pause.
        var onPause: () -> Void = {}

        func makeRun(_ targets: [BroadcastTarget], text: String = "Hello") -> BroadcastRun {
            BroadcastRun(
                targets: targets,
                text: text,
                send: { target, text in
                    self.sentRoomIds.append(target.roomId)
                    self.sentTexts.insert(text)
                    self.onSend(target.roomId)
                    if self.failingRoomIds.contains(target.roomId) {
                        throw SendFailure()
                    }
                },
                pause: {
                    self.pauseCount += 1
                    self.onPause()
                }
            )
        }
    }

    private func makeTargets(_ ids: [String]) -> [BroadcastTarget] {
        ids.map { BroadcastTarget(id: $0, row: ChatListRowModel(id: $0, title: $0), roomId: $0) }
    }

    @Test func allTargetsSucceedInOrder() async {
        let recorder = Recorder()
        let run = recorder.makeRun(makeTargets(["!a", "!b", "!c"]), text: "Lunch")
        #expect(run.phase == .idle)
        #expect(run.summary == BroadcastSummary(sent: 0, failed: 0, notSent: 3))

        await run.start()

        #expect(run.phase == .finished)
        #expect(recorder.sentRoomIds == ["!a", "!b", "!c"])
        #expect(recorder.sentTexts == ["Lunch"])
        #expect(run.summary == BroadcastSummary(sent: 3, failed: 0, notSent: 0))
        #expect(run.summary.completed == 3)
        #expect(run.summary.total == 3)
        // A pause between two sends, none before the first or after the last.
        #expect(recorder.pauseCount == 2)
    }

    @Test func oneSendAtATime() async {
        let recorder = Recorder()
        let run = recorder.makeRun(makeTargets(["!a", "!b", "!c"]))
        var sendingCounts: [Int] = []
        recorder.onSend = { _ in
            sendingCounts.append(run.states.values.filter { $0 == .sending }.count)
        }
        await run.start()
        #expect(sendingCounts == [1, 1, 1])
    }

    @Test func failureDoesNotStopTheRun() async {
        let recorder = Recorder()
        recorder.failingRoomIds = ["!b"]
        let run = recorder.makeRun(makeTargets(["!a", "!b", "!c"]))

        await run.start()

        #expect(recorder.sentRoomIds == ["!a", "!b", "!c"])
        #expect(run.state(of: "!a") == .sent)
        #expect(run.state(of: "!b") == .failed("The room refused the message."))
        #expect(run.state(of: "!c") == .sent)
        #expect(run.summary == BroadcastSummary(sent: 2, failed: 1, notSent: 0))
        #expect(run.phase == .finished)
    }

    /// A stop during a send: that send finishes, the rest stay waiting.
    @Test func stopDuringSendFinishesThatSend() async {
        let recorder = Recorder()
        let run = recorder.makeRun(makeTargets(["!a", "!b", "!c", "!d"]))
        var phaseAfterStop: BroadcastRun.Phase?
        recorder.onSend = { roomId in
            if roomId == "!b" {
                run.stop()
                phaseAfterStop = run.phase
            }
        }

        await run.start()

        #expect(phaseAfterStop == .stopping)
        #expect(recorder.sentRoomIds == ["!a", "!b"])
        #expect(run.state(of: "!b") == .sent)
        #expect(run.state(of: "!c") == .waiting)
        #expect(run.state(of: "!d") == .waiting)
        #expect(run.summary == BroadcastSummary(sent: 2, failed: 0, notSent: 2))
        #expect(run.phase == .finished)
        #expect(!run.isActive)
    }

    /// A stop in the pause: the next send does not start.
    @Test func stopDuringPauseSendsNothingMore() async {
        let recorder = Recorder()
        let run = recorder.makeRun(makeTargets(["!a", "!b", "!c"]))
        recorder.onPause = { run.stop() }

        await run.start()

        #expect(recorder.sentRoomIds == ["!a"])
        #expect(run.summary == BroadcastSummary(sent: 1, failed: 0, notSent: 2))
        #expect(run.phase == .finished)
    }

    @Test func retryFailedSendsOnlyToTheFailedTargets() async {
        let recorder = Recorder()
        recorder.failingRoomIds = ["!b", "!d"]
        let run = recorder.makeRun(makeTargets(["!a", "!b", "!c", "!d"]))
        await run.start()
        #expect(run.summary == BroadcastSummary(sent: 2, failed: 2, notSent: 0))

        // `!b` works now, `!d` still fails.
        recorder.failingRoomIds = ["!d"]
        recorder.sentRoomIds = []
        await run.retryFailed()

        #expect(recorder.sentRoomIds == ["!b", "!d"])
        #expect(run.state(of: "!b") == .sent)
        #expect(run.summary == BroadcastSummary(sent: 3, failed: 1, notSent: 0))
        #expect(run.phase == .finished)
    }

    /// A retry does not send to the targets a stop left waiting.
    @Test func retryAfterStopLeavesWaitingTargetsAlone() async {
        let recorder = Recorder()
        recorder.failingRoomIds = ["!a"]
        let run = recorder.makeRun(makeTargets(["!a", "!b", "!c"]))
        recorder.onSend = { roomId in
            if roomId == "!b" {
                run.stop()
            }
        }
        await run.start()
        #expect(run.summary == BroadcastSummary(sent: 1, failed: 1, notSent: 1))

        recorder.failingRoomIds = []
        recorder.onSend = { _ in }
        recorder.sentRoomIds = []
        await run.retryFailed()

        #expect(recorder.sentRoomIds == ["!a"])
        #expect(run.state(of: "!c") == .waiting)
        #expect(run.summary == BroadcastSummary(sent: 2, failed: 0, notSent: 1))
    }

    @Test func nothingIsSentTwice() async {
        let recorder = Recorder()
        let run = recorder.makeRun(makeTargets(["!a", "!b"]))
        await run.start()
        // A second start, and a retry with no failure, send nothing.
        await run.start()
        await run.retryFailed()
        #expect(recorder.sentRoomIds == ["!a", "!b"])
    }

    /// Two targets with the same room, or the same ID, give one send.
    @Test func duplicateTargetsAreDropped() async {
        let recorder = Recorder()
        let row = ChatListRowModel(id: "x", title: "x")
        let run = recorder.makeRun([
            BroadcastTarget(id: "!a", row: row, roomId: "!a"),
            BroadcastTarget(id: "m", row: row, roomId: "!a", mergedChatId: "m"),
            BroadcastTarget(id: "!a", row: row, roomId: "!b"),
            BroadcastTarget(id: "!c", row: row, roomId: "!c"),
        ])
        await run.start()
        #expect(run.targets.map(\.id) == ["!a", "!c"])
        #expect(recorder.sentRoomIds == ["!a", "!c"])
    }

    @Test func retryAndStopDoNothingBeforeTheRun() async {
        let recorder = Recorder()
        let run = recorder.makeRun(makeTargets(["!a"]))
        run.stop()
        await run.retryFailed()
        #expect(run.phase == .idle)
        #expect(recorder.sentRoomIds.isEmpty)
    }

    @Test func reasonIsShortAndOnOneLine() {
        struct Plain: Error {}
        struct Long: LocalizedError {
            var errorDescription: String? {
                String(repeating: "x", count: 500)
            }
        }
        struct Blank: LocalizedError {
            var errorDescription: String? {
                " \n "
            }
        }
        #expect(BroadcastRun.reason(for: SendFailure()) == "The room refused the message.")
        #expect(BroadcastRun.reason(for: Plain()) == "Plain()")
        #expect(BroadcastRun.reason(for: Long()).count == BroadcastRun.reasonLimit)
        #expect(BroadcastRun.reason(for: Blank()) == "The message was not sent.")
    }
}
