@testable import MactrixiOS
import XCTest

/// MATRIX-86: composer send rules and reply state.
@MainActor
final class ComposerModelTests: XCTestCase {
    private struct Refused: Error {}

    /// A target that records sends and can refuse them.
    private final class RecordingTarget: ComposerTarget {
        var reply: ComposerReply?
        var sent: [String] = []
        var refuses = false

        func cancelReply() {
            reply = nil
        }

        func send(body: String) async throws {
            if refuses { throw Refused() }
            sent.append(body)
        }

        func noteTyping() async {}
    }

    private let replyTarget = ComposerReply(id: "$event", senderName: "Ada", preview: "Lunch?")

    func testOutgoingBodyTrimsSurroundingWhitespaceOnly() {
        XCTAssertEqual(ComposerRules.outgoingBody("  hello \n"), "hello")
        XCTAssertEqual(ComposerRules.outgoingBody("\nline one\nline two\n\n"), "line one\nline two")
    }

    func testOutgoingBodyIsNilForBlankText() {
        XCTAssertNil(ComposerRules.outgoingBody(""))
        XCTAssertNil(ComposerRules.outgoingBody(" \n\t "))
    }

    func testCanSendNeedsTextAndNoSendInFlight() {
        XCTAssertTrue(ComposerRules.canSend(text: "hi", isSending: false))
        XCTAssertFalse(ComposerRules.canSend(text: "hi", isSending: true))
        XCTAssertFalse(ComposerRules.canSend(text: "  ", isSending: false))
    }

    func testSendTrimsClearsTextAndClearsReply() async {
        let target = RecordingTarget()
        target.reply = replyTarget
        let model = ComposerModel()
        model.text = "  on my way \n"

        await model.send(to: target)

        XCTAssertEqual(target.sent, ["on my way"])
        XCTAssertEqual(model.text, "")
        XCTAssertNil(target.reply)
        XCTAssertFalse(model.isSending)
    }

    func testBlankTextSendsNothing() async {
        let target = RecordingTarget()
        target.reply = replyTarget
        let model = ComposerModel()
        model.text = "\n\n"

        await model.send(to: target)

        XCTAssertTrue(target.sent.isEmpty)
        XCTAssertEqual(model.text, "\n\n")
        XCTAssertEqual(target.reply, replyTarget)
    }

    func testRefusedSendRestoresTextAndKeepsReply() async {
        let target = RecordingTarget()
        target.reply = replyTarget
        target.refuses = true
        let model = ComposerModel()
        model.text = "draft"

        await model.send(to: target)

        XCTAssertEqual(model.text, "draft")
        XCTAssertEqual(target.reply, replyTarget)
        XCTAssertFalse(model.isSending)
    }
}
