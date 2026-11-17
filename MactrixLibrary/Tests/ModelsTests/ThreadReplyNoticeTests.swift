@testable import Models
import Testing

/// The rule that maps the send state of a thread reply to the notice above
/// the main composer (MATRIX-173).
struct ThreadReplyNoticeTests {
    private func echo(_ state: LocalSendState?, root: String = "$root", id: String = "txn1") -> ThreadReplyEcho {
        ThreadReplyEcho(threadRoot: root, itemId: id, sendState: state)
    }

    private let failed = LocalSendState.sendingFailed(message: "no network", isRecoverable: true)
    private let wedged = LocalSendState.sendingFailed(message: "rejected", isRecoverable: false)

    // MARK: One echo

    @Test func pendingSendWithRunningQueueGivesNoNotice() {
        #expect(ThreadReplyNotice.notice(for: echo(.sending), isSendQueueEnabled: true) == nil)
    }

    @Test func pendingSendWithStoppedQueueGivesNotice() {
        #expect(
            ThreadReplyNotice.notice(for: echo(.sending), isSendQueueEnabled: false)
                == ThreadReplyNotice(threadRoot: "$root", itemId: "txn1", retry: .enableSendQueue)
        )
    }

    @Test(arguments: [true, false])
    func recoverableFailureGivesNoticeThatStartsTheQueue(isSendQueueEnabled: Bool) {
        #expect(
            ThreadReplyNotice.notice(for: echo(failed), isSendQueueEnabled: isSendQueueEnabled)
                == ThreadReplyNotice(threadRoot: "$root", itemId: "txn1", retry: .enableSendQueue)
        )
    }

    @Test(arguments: [true, false])
    func unrecoverableFailureGivesNoticeThatResends(isSendQueueEnabled: Bool) {
        #expect(
            ThreadReplyNotice.notice(for: echo(wedged), isSendQueueEnabled: isSendQueueEnabled)
                == ThreadReplyNotice(threadRoot: "$root", itemId: "txn1", retry: .resend)
        )
    }

    @Test(arguments: [true, false])
    func sentMessageGivesNoNotice(isSendQueueEnabled: Bool) {
        #expect(ThreadReplyNotice.notice(for: echo(.sent), isSendQueueEnabled: isSendQueueEnabled) == nil)
    }

    @Test(arguments: [true, false])
    func remoteEventGivesNoNotice(isSendQueueEnabled: Bool) {
        #expect(ThreadReplyNotice.notice(for: echo(nil), isSendQueueEnabled: isSendQueueEnabled) == nil)
    }

    // MARK: The one notice of the main column

    @Test func noEchoesGiveNoNotice() {
        #expect(ThreadReplyNotice.first(in: [], isSendQueueEnabled: true, shownThreadRoot: nil) == nil)
    }

    @Test func firstEchoThatNeedsANoticeGetsIt() {
        let echoes = [
            echo(.sent, id: "txn1"),
            echo(.sending, id: "txn2"),
            echo(wedged, id: "txn3"),
            echo(failed, id: "txn4"),
        ]
        #expect(
            ThreadReplyNotice.first(in: echoes, isSendQueueEnabled: true, shownThreadRoot: nil)
                == ThreadReplyNotice(threadRoot: "$root", itemId: "txn3", retry: .resend)
        )
    }

    @Test func noticeGoesAwayWhenTheMessageIsSent() {
        #expect(ThreadReplyNotice.first(in: [echo(failed)], isSendQueueEnabled: true, shownThreadRoot: nil) != nil)
        #expect(ThreadReplyNotice.first(in: [echo(.sent)], isSendQueueEnabled: true, shownThreadRoot: nil) == nil)
        // The remote echo replaced the local echo.
        #expect(ThreadReplyNotice.first(in: [echo(nil)], isSendQueueEnabled: true, shownThreadRoot: nil) == nil)
    }

    @Test func threadInThePanelGivesNoNotice() {
        #expect(ThreadReplyNotice.first(in: [echo(failed)], isSendQueueEnabled: true, shownThreadRoot: "$root") == nil)
    }

    @Test func otherThreadInThePanelDoesNotHideTheNotice() {
        let echoes = [echo(failed, root: "$shown", id: "txn1"), echo(failed, root: "$other", id: "txn2")]
        #expect(
            ThreadReplyNotice.first(in: echoes, isSendQueueEnabled: true, shownThreadRoot: "$shown")
                == ThreadReplyNotice(threadRoot: "$other", itemId: "txn2", retry: .enableSendQueue)
        )
    }
}
