@testable import Core
import Foundation
import MatrixRustSDK
import Models
import Testing

/// MATRIX-209: the SDK's edit revisions, mapped to the edit history's
/// version bodies.
struct EditHistoryMappingTests {
    private typealias Body = EditHistoryVersion<MatrixRustSDK.MessageContent>.Body

    private static func msgLike(_ kind: MatrixRustSDK.MsgLikeKind) -> MatrixRustSDK.TimelineItemContent {
        .msgLike(content: MatrixRustSDK.MsgLikeContent(kind: kind, inReplyTo: nil, threadRoot: nil, threadSummary: nil))
    }

    @Test func messageRevisionKeepsItsContent() {
        let text = MatrixRustSDK.MessageContent(
            msgType: .text(content: MatrixRustSDK.TextMessageContent(body: "Final text", formatted: nil)),
            body: "Final text",
            isEdited: true,
            mentions: nil
        )
        guard case let .message(message) = Body(Self.msgLike(.message(content: text))) else {
            Issue.record("a message revision maps to a message body")
            return
        }
        #expect(message.body == "Final text")
    }

    @Test func undecryptableRevisionMapsToItsCause() {
        let body = Body(Self.msgLike(.unableToDecrypt(msg: .unknown)))
        guard case let .unableToDecrypt(cause) = body else {
            Issue.record("an undecryptable revision maps to an unable-to-decrypt body")
            return
        }
        #expect(cause == .unknown)
    }

    @Test func redactedRevisionIsDescribed() {
        guard case let .other(description) = Body(Self.msgLike(.redacted)) else {
            Issue.record("a redacted revision maps to a described body")
            return
        }
        #expect(description == "Redacted")
    }
}
