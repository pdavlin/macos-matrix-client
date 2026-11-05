import Foundation
@testable import Models
import Testing

/// An event whose only configurable field is its upload state.
private struct UploadingEvent: EventTimelineItem {
    var mediaUploadState: MediaUploadState?

    var isRemote: Bool { false }
    var sender: String { "@ada:example.org" }
    var senderProfileDetails: ProfileDetails { .unavailable }
    var isOwn: Bool { true }
    var isEditable: Bool { false }
    var date: Date { Date(timeIntervalSince1970: 0) }
    var sendState: LocalSendState? { .sending }
    var localCreatedAt: UInt64? { nil }
    var userReadReceipts: [String: Receipt] { [:] }
    var canBeRepliedTo: Bool { false }
    var userId: String { sender }
    var displayName: String? { nil }
    var avatarUrl: String? { nil }
}

/// MATRIX-107: the upload indicator's state, the progress tick throttle, and
/// the claim that progress never reaches the height fingerprint.
struct MediaUploadTests {
    private func uploading(_ current: UInt64, of total: UInt64, index: UInt64 = 0) -> MediaUploadState {
        .uploading(MediaUploadSample(index: index, current: current, total: total))
    }

    private func row(
        _ state: MediaUploadState?,
        kind: MessageRowKind = .media,
        fingerprint: TimelineRowHeightFingerprint = .stub(body: .init(variant: "video", text: ""))
    ) -> TimelineRow {
        .message(uniqueId: "echo-1", event: UploadingEvent(mediaUploadState: state), kind: kind, heightFingerprint: fingerprint)
    }

    // MARK: - Sample

    @Test
    func percentRoundsDownSoTheRowNeverClaimsDoneEarly() {
        #expect(MediaUploadSample(index: 0, current: 996, total: 1000).percent == 99)
        #expect(MediaUploadSample(index: 0, current: 1000, total: 1000).percent == 100)
        #expect(MediaUploadSample(index: 0, current: 0, total: 1000).percent == 0)
    }

    @Test
    func zeroTotalIsIndeterminate() {
        let sample = MediaUploadSample(index: 0, current: 5, total: 0)

        #expect(sample.fraction == nil)
        #expect(sample.percent == nil)
        #expect(!sample.isComplete)
    }

    @Test
    func anEstimateThatOvershootsItsTotalIsClamped() {
        let sample = MediaUploadSample(index: 0, current: 130, total: 100)

        #expect(sample.fraction == 1)
        #expect(sample.percent == 100)
        #expect(sample.isComplete)
    }

    @Test
    func queuedIsIndeterminate() {
        #expect(MediaUploadState.queued.fraction == nil)
        #expect(MediaUploadState.queued.percent == nil)
        #expect(uploading(1, of: 4).percent == 25)
    }

    // MARK: - Row access

    @Test
    func mediaAndAttachmentRowsExposeTheUploadState() {
        #expect(row(uploading(1, of: 2), kind: .media).mediaUploadState == uploading(1, of: 2))
        #expect(row(.queued, kind: .attachment).mediaUploadState == .queued)
    }

    /// A text echo is queued too, but it draws no upload indicator.
    @Test
    func textAndOtherRowsHaveNoUploadState() {
        #expect(row(.queued, kind: .text).mediaUploadState == nil)
        #expect(row(.queued, kind: .other).mediaUploadState == nil)
    }

    @Test
    func eventsWithoutASendQueueDefaultToNoUploadState() {
        #expect(MockEventTimelineItem().mediaUploadState == nil)
    }

    // MARK: - Height neutrality (MATRIX-63)

    /// The indicator is an overlay, so the fingerprint has no upload field: a
    /// progress tick, the queued-to-uploading swap, and the end of the upload
    /// all keep the row at the height it already measured.
    @Test
    func uploadProgressChangesAreHeightNeutral() {
        let states: [MediaUploadState?] = [.queued, uploading(0, of: 100), uploading(42, of: 100), uploading(1, of: 3, index: 1), nil]

        for (old, new) in zip(states, states.dropFirst()) {
            #expect(TimelineRowHeightFingerprint.heightIsUnchanged(from: row(old), to: row(new)))
        }
    }

    /// The failure banner is in the layout, so a failed upload is not
    /// height-neutral. The send failure stays the only send-state height input.
    @Test
    func uploadFailureIsNotHeightNeutral() {
        let uploadingRow = row(uploading(42, of: 100))
        let failedRow = row(
            nil,
            fingerprint: .stub(body: .init(variant: "video", text: ""), sendFailureMessage: "the server rejected the file")
        )

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: uploadingRow, to: failedRow))
    }

    // MARK: - Throttle rule

    @Test
    func samePercentIsDroppedHoweverLongAgo() {
        #expect(!MediaUploadThrottle.isWorthRedrawing(
            from: uploading(420, of: 1000),
            to: uploading(425, of: 1000),
            elapsed: 5,
            minimumInterval: 0.1
        ))
    }

    @Test
    func aNewPercentWaitsForTheMinimumInterval() {
        let old = uploading(42, of: 100)
        let new = uploading(43, of: 100)

        #expect(!MediaUploadThrottle.isWorthRedrawing(from: old, to: new, elapsed: 0.05, minimumInterval: 0.1))
        #expect(MediaUploadThrottle.isWorthRedrawing(from: old, to: new, elapsed: 0.1, minimumInterval: 0.1))
    }

    @Test
    func indicatorKindChangesAlwaysPass() {
        #expect(MediaUploadThrottle.isWorthRedrawing(from: .queued, to: uploading(0, of: 10), elapsed: 0, minimumInterval: 0.1))
        #expect(MediaUploadThrottle.isWorthRedrawing(from: uploading(5, of: 10), to: .queued, elapsed: 0, minimumInterval: 0.1))
        #expect(MediaUploadThrottle.isWorthRedrawing(from: .queued, to: .queued, elapsed: 0, minimumInterval: 0.1))
    }

    @Test
    func aNewStepAlwaysPasses() {
        #expect(MediaUploadThrottle.isWorthRedrawing(
            from: uploading(10, of: 100, index: 0),
            to: uploading(10, of: 100, index: 1),
            elapsed: 0,
            minimumInterval: 0.1
        ))
    }

    @Test
    func completionAlwaysPassesSoTheRowDoesNotStopAt99() {
        #expect(MediaUploadThrottle.isWorthRedrawing(
            from: uploading(995, of: 1000),
            to: uploading(1000, of: 1000),
            elapsed: 0.01,
            minimumInterval: 0.1
        ))
    }

    // MARK: - Throttle bookkeeping

    @Test
    func aTickStormIsCappedAtTheMinimumInterval() {
        var throttle = MediaUploadThrottle()
        var admitted = 0
        // One second of ticks every 5 ms, each moving the upload 0.25%.
        for tick in 0 ..< 200 {
            let state = uploading(UInt64(tick) * 5, of: 2000)
            if throttle.admit(rowId: "echo-1", state: state, at: Double(tick) * 0.005) {
                admitted += 1
            }
        }

        // The first tick, then at most one per 100 ms.
        #expect(admitted <= 11)
        #expect(admitted >= 10)
    }

    @Test
    func rowsAreThrottledIndependently() {
        var throttle = MediaUploadThrottle()

        let admitted1: Bool = throttle.admit(rowId: "a", state: uploading(1, of: 100), at: 0)

        #expect(admitted1)
        let admitted2: Bool = throttle.admit(rowId: "b", state: uploading(1, of: 100), at: 0.01)
        #expect(admitted2)
        let admitted3: Bool = throttle.admit(rowId: "a", state: uploading(2, of: 100), at: 0.02)
        #expect(!admitted3)
    }

    @Test
    func rowsWithoutAnUploadAlwaysPassAndAreNotTracked() {
        var throttle = MediaUploadThrottle()

        let admitted4: Bool = throttle.admit(rowId: "text", state: nil, at: 0)

        #expect(admitted4)
        let admitted5: Bool = throttle.admit(rowId: "text", state: nil, at: 0)
        #expect(admitted5)
        #expect(throttle.trackedRowCount == 0)
    }

    @Test
    func theEndOfAnUploadPassesAndStopsTracking() {
        var throttle = MediaUploadThrottle()
        _ = throttle.admit(rowId: "echo-1", state: uploading(50, of: 100), at: 0)

        let admitted6: Bool = throttle.admit(rowId: "echo-1", state: nil, at: 0.001)

        #expect(admitted6)
        #expect(throttle.trackedRowCount == 0)
    }

    @Test
    func forgetAndRemoveAllStopTracking() {
        var throttle = MediaUploadThrottle()
        _ = throttle.admit(rowId: "a", state: .queued, at: 0)
        _ = throttle.admit(rowId: "b", state: .queued, at: 0)

        throttle.forget(rowId: "a")
        #expect(throttle.trackedRowCount == 1)
        throttle.removeAll()
        #expect(throttle.trackedRowCount == 0)
    }

    /// A dropped tick is not recorded, so the interval runs from the last
    /// redraw, not from the last tick.
    @Test
    func theIntervalRunsFromTheLastRedraw() {
        var throttle = MediaUploadThrottle()

        let admitted7: Bool = throttle.admit(rowId: "a", state: uploading(10, of: 100), at: 0)

        #expect(admitted7)
        let admitted8: Bool = throttle.admit(rowId: "a", state: uploading(11, of: 100), at: 0.06)
        #expect(!admitted8)
        let admitted9: Bool = throttle.admit(rowId: "a", state: uploading(12, of: 100), at: 0.1)
        #expect(admitted9)
    }
}
