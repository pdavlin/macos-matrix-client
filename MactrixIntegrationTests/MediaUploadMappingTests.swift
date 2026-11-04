import Core
import Foundation
import MatrixRustSDK
import Models
import XCTest

/// MATRIX-107: the SDK send state of a local echo, mapped into the upload
/// indicator state, and the claim that upload progress never reaches the
/// height fingerprint (MATRIX-63) when it comes from real SDK items.
final class MediaUploadMappingTests: XCTestCase {
    // MARK: - Send state to upload state

    func testQueuedEchoHasAnIndeterminateUploadState() {
        XCTAssertEqual(makeEcho(sendState: .notSentYet(progress: nil)).mediaUploadState, .queued)
    }

    func testUploadProgressMapsIndexCurrentAndTotal() {
        let echo = makeEcho(sendState: uploading(index: 1, current: 420, total: 1000))

        XCTAssertEqual(
            echo.mediaUploadState,
            .uploading(Models.MediaUploadSample(index: 1, current: 420, total: 1000))
        )
        XCTAssertEqual(echo.mediaUploadState?.percent, 42)
    }

    func testFailedAndRemoteItemsHaveNoUploadState() {
        XCTAssertNil(
            makeEcho(sendState: .sendingFailed(error: .missingMediaContent, isRecoverable: false)).mediaUploadState
        )
        XCTAssertNil(makeEcho(sendState: nil).mediaUploadState)
    }

    /// The row reads the state through the model protocol, so the SDK member
    /// has to be the protocol's witness, not a shadow of its `nil` default.
    func testUploadStateReachesTheModelProtocol() {
        let echo: any Models.EventTimelineItem = makeEcho(sendState: .notSentYet(progress: nil))

        XCTAssertEqual(echo.mediaUploadState, .queued)
    }

    // MARK: - Height neutrality (MATRIX-63)

    /// Every progress tick, and the swap from queued to uploading, keeps the
    /// fingerprint the SDK mapping builds. The indicator is an overlay.
    func testUploadProgressKeepsTheHeightFingerprint() {
        let content = makeMsgLikeContent()
        let states: [MatrixRustSDK.EventSendState] = [
            .notSentYet(progress: nil),
            uploading(index: 0, current: 0, total: 1000),
            uploading(index: 0, current: 420, total: 1000),
            uploading(index: 1, current: 999, total: 1000),
            uploading(index: 1, current: 1000, total: 1000),
        ]
        let fingerprints = states.map { content.heightFingerprint(event: makeEcho(sendState: $0)) }

        for fingerprint in fingerprints.dropFirst() {
            XCTAssertEqual(fingerprint, fingerprints[0])
        }
    }

    /// The end of the upload is height-neutral too: once the send state
    /// leaves `.notSentYet`, the row draws without the overlay at the same
    /// height. (A nil send state stands in for the end; the `.sent` case is
    /// not in the verified FFI list for this story.)
    func testTheEndOfTheUploadKeepsTheHeightFingerprint() {
        let content = makeMsgLikeContent()
        let uploadingEcho = makeEcho(sendState: uploading(index: 0, current: 500, total: 1000))
        let finishedEcho = makeEcho(sendState: nil)

        XCTAssertEqual(content.heightFingerprint(event: uploadingEcho), content.heightFingerprint(event: finishedEcho))
    }

    /// A failed upload draws the failure banner in the layout, so it must not
    /// share the uploading row's fingerprint.
    func testAFailedUploadChangesTheHeightFingerprint() {
        let content = makeMsgLikeContent()
        let uploadingEcho = makeEcho(sendState: uploading(index: 0, current: 500, total: 1000))
        let failedEcho = makeEcho(sendState: .sendingFailed(error: .missingMediaContent, isRecoverable: false))

        XCTAssertNotEqual(content.heightFingerprint(event: uploadingEcho), content.heightFingerprint(event: failedEcho))
    }

    // MARK: - Fixtures

    private func uploading(index: UInt64, current: UInt64, total: UInt64) -> MatrixRustSDK.EventSendState {
        .notSentYet(
            progress: MatrixRustSDK.MediaUploadProgress(
                index: index,
                progress: MatrixRustSDK.AbstractProgress(current: current, total: total)
            )
        )
    }

    private func makeEcho(sendState: MatrixRustSDK.EventSendState?) -> MatrixRustSDK.EventTimelineItem {
        MatrixRustSDK.EventTimelineItem(
            isRemote: false,
            eventOrTransactionId: .transactionId(transactionId: "txn-1"),
            sender: "@ada:example.org",
            senderProfile: .unavailable,
            forwarder: nil,
            forwarderProfile: nil,
            isOwn: true,
            isEditable: false,
            content: .msgLike(content: makeMsgLikeContent()),
            timestamp: 1_700_000_000_000,
            localSendState: sendState,
            localCreatedAt: nil,
            readReceipts: [:],
            origin: nil,
            canBeRepliedTo: false,
            lazyProvider: MatrixRustSDK.LazyTimelineItemProvider(noHandle: .init())
        )
    }

    /// Redacted content: the fingerprint's body branch is not what these
    /// tests are about, and it needs no media constructor.
    private func makeMsgLikeContent() -> MatrixRustSDK.MsgLikeContent {
        MatrixRustSDK.MsgLikeContent(
            kind: .redacted,
            reactions: [],
            inReplyTo: nil,
            threadRoot: nil,
            threadSummary: nil
        )
    }
}
