import Foundation
@testable import Models
import Testing

extension TimelineRowHeightFingerprint {
    /// A message fingerprint with every field at a neutral value, so each test
    /// changes exactly the one field it is about.
    static func stub(
        body: MessageBodyGeometry = .init(variant: "text", text: "hello"),
        replyToEventId: String? = nil,
        hasThreadSummary: Bool = false,
        sendFailureMessage: String? = nil,
        senderName: String = "@ada:example.org",
        pills: [ReactionPillGeometry] = [],
        hasReadReceipts: Bool = false
    ) -> TimelineRowHeightFingerprint {
        TimelineRowHeightFingerprint(
            body: body,
            replyToEventId: replyToEventId,
            hasThreadSummary: hasThreadSummary,
            sendFailureMessage: sendFailureMessage,
            senderName: senderName,
            reactions: ReactionStripGeometry(pills: pills, hasReadReceipts: hasReadReceipts)
        )
    }
}

/// MATRIX-63: the height-relevant fingerprint, as pure logic.
///
/// The rule under test is one-directional. Equal fingerprints must mean the
/// height cannot have changed; unequal ones only mean the row gets measured,
/// which is never wrong, only slower. Every test that expects a re-measure is
/// therefore a correctness test, and every test that expects a skip is the
/// performance claim.
struct TimelineRowHeightFingerprintTests {
    private func messageRow(
        uniqueId: String = "u1",
        _ fingerprint: TimelineRowHeightFingerprint
    ) -> TimelineRow {
        .message(uniqueId: uniqueId, event: MockEventTimelineItem(), kind: .text, heightFingerprint: fingerprint)
    }

    private func pill(_ key: String, _ senderCount: Int) -> ReactionPillGeometry {
        ReactionPillGeometry(key: key, senderCount: senderCount)
    }

    // MARK: - Reaction tallies: the storm's height-neutral majority

    @Test
    func senderCountOnlyReactionChangeIsHeightNeutral() {
        let before = messageRow(.stub(pills: [pill("👍", 3)]))
        let after = messageRow(.stub(pills: [pill("👍", 4)]))

        #expect(TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func senderCountChangeOnOneOfSeveralKeysIsHeightNeutral() {
        let before = messageRow(.stub(pills: [pill("👍", 2), pill("🎉", 9), pill("❤️", 1)]))
        let after = messageRow(.stub(pills: [pill("👍", 2), pill("🎉", 8), pill("❤️", 1)]))

        #expect(TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func tallyCrossingADigitBoundaryIsNotHeightNeutral() {
        // The count label gains a digit, which widens the pill. Width is what
        // pushes the strip into compression, and compression is what can wrap a
        // pill's text onto a second line.
        let before = messageRow(.stub(pills: [pill("👍", 9)]))
        let after = messageRow(.stub(pills: [pill("👍", 10)]))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    // MARK: - Reaction pill geometry: the cases that must re-measure

    @Test
    func firstReactionIsNotHeightNeutral() {
        // The strip goes from drawing nothing to drawing a pill, and both
        // paddings around it switch on emptiness.
        let before = messageRow(.stub(pills: []))
        let after = messageRow(.stub(pills: [pill("👍", 1)]))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func lastReactionRemovedIsNotHeightNeutral() {
        let before = messageRow(.stub(pills: [pill("👍", 1)]))
        let after = messageRow(.stub(pills: []))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func newDistinctKeyIsNotHeightNeutral() {
        // A new pill widens the strip, so it carries wrap risk even though the
        // pill itself is one line tall.
        let before = messageRow(.stub(pills: [pill("👍", 2)]))
        let after = messageRow(.stub(pills: [pill("👍", 2), pill("🎉", 1)]))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func replacingAKeyAtTheSameTallyIsNotHeightNeutral() {
        // Same pill count, same tally, different glyph: "👍" and "lgtm" do not
        // lay out to the same width.
        let before = messageRow(.stub(pills: [pill("👍", 2)]))
        let after = messageRow(.stub(pills: [pill("lgtm", 2)]))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func readReceiptAppearingIsNotHeightNeutral() {
        // Receipts share the strip and flip its top padding through
        // `hasBottomContent`.
        let before = messageRow(.stub(hasReadReceipts: false))
        let after = messageRow(.stub(hasReadReceipts: true))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    // MARK: - Body content

    @Test
    func editedBodyIsNotHeightNeutral() {
        let before = messageRow(.stub(body: .init(variant: "text", text: "one line")))
        let after = messageRow(
            .stub(body: .init(variant: "text", text: "a much longer body that wraps", isEdited: true))
        )

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func editedMarkerAloneIsNotHeightNeutral() {
        // The marker is a line of its own under the body, so it moves the height
        // even when the text it annotates is unchanged.
        let before = messageRow(.stub(body: .init(variant: "text", text: "same", isEdited: false)))
        let after = messageRow(.stub(body: .init(variant: "text", text: "same", isEdited: true)))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func formattedBodyChangeIsNotHeightNeutral() {
        // The HTML body is what a formatted message renders, so it can change
        // the line count while the plain body stays put.
        let before = messageRow(.stub(body: .init(variant: "text", text: "x", formattedText: "<p>x</p>")))
        let after = messageRow(
            .stub(body: .init(variant: "text", text: "x", formattedText: "<p>x</p><p>y</p>"))
        )

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func sameBodyTextInADifferentBranchIsNotHeightNeutral() {
        // `MessageRowKind` cannot separate a poll from a redaction — both are
        // `.other` — so the variant has to.
        let before = messageRow(.stub(body: .init(variant: "poll", text: "")))
        let after = messageRow(.stub(body: .init(variant: "redacted", text: "")))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func mediaDimensionsChangingIsNotHeightNeutral() {
        let before = messageRow(
            .stub(body: .init(variant: "image", text: "", mediaWidth: 800, mediaHeight: 600))
        )
        let after = messageRow(
            .stub(body: .init(variant: "image", text: "", mediaWidth: 800, mediaHeight: 1200))
        )

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func mediaCaptionChangingIsNotHeightNeutral() {
        let before = messageRow(.stub(body: .init(variant: "image", text: "", secondaryText: nil)))
        let after = messageRow(.stub(body: .init(variant: "image", text: "", secondaryText: "a caption")))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func videoThumbnailArrivingIsNotHeightNeutral() {
        let before = messageRow(.stub(body: .init(variant: "video", text: "", hasMediaThumbnail: false)))
        let after = messageRow(.stub(body: .init(variant: "video", text: "", hasMediaThumbnail: true)))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    // MARK: - Decorations around the body

    @Test
    func replyPreviewAppearingIsNotHeightNeutral() {
        let before = messageRow(.stub(replyToEventId: nil))
        let after = messageRow(.stub(replyToEventId: "$abc"))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func threadSummaryAppearingIsNotHeightNeutral() {
        let before = messageRow(.stub(hasThreadSummary: false))
        let after = messageRow(.stub(hasThreadSummary: true))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func sendFailureBannerAppearingIsNotHeightNeutral() {
        let before = messageRow(.stub(sendFailureMessage: nil))
        let after = messageRow(.stub(sendFailureMessage: "the homeserver said no"))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func senderNameResolvingIsNotHeightNeutral() {
        // A profile resolving replaces the user ID with a display name in the
        // header, and that line can wrap.
        let before = messageRow(.stub(senderName: "@ada:example.org"))
        let after = messageRow(.stub(senderName: "Ada Lovelace"))

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    // MARK: - The conservative guards

    @Test
    func identicalFingerprintsOnDifferentIdentitiesAreNotHeightNeutral() {
        let before = messageRow(uniqueId: "u1", .stub())
        let after = messageRow(uniqueId: "u2", .stub())

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: before, to: after))
    }

    @Test
    func rowsWithoutAFingerprintAreNeverHeightNeutral() {
        let state = TimelineRow.state(uniqueId: "u1", event: MockEventTimelineItem(), name: "joined room")
        let virtual = TimelineRow.virtual(uniqueId: "u1", item: .readMarker)

        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: state, to: state))
        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: virtual, to: virtual))
        #expect(!TimelineRowHeightFingerprint.heightIsUnchanged(from: state, to: messageRow(.stub())))
    }

    @Test
    func anUnchangedRowIsHeightNeutral() {
        let fingerprint = TimelineRowHeightFingerprint.stub(pills: [pill("👍", 1)])

        #expect(
            TimelineRowHeightFingerprint.heightIsUnchanged(
                from: messageRow(fingerprint),
                to: messageRow(fingerprint)
            )
        )
    }

    // MARK: - Digit arithmetic

    @Test(arguments: [(0, 1), (1, 1), (9, 1), (10, 2), (99, 2), (100, 3), (1000, 4)])
    func decimalDigitsCountsWithoutBuildingAString(count: Int, expected: Int) {
        #expect(ReactionPillGeometry.decimalDigits(of: count) == expected)
        #expect(ReactionPillGeometry(key: "👍", senderCount: count).countDigits == expected)
    }
}
