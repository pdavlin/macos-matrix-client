@testable import MactrixiOS
import Models
import SnapshotTesting
import SwiftUI
import Tokens
import UI
import UIKit
import XCTest

/// MATRIX-249: the iOS reaction surfaces, in light and dark. A row with
/// reaction chips (an own reaction, another, and a custom emoji), the card
/// that a long press on a chip shows, and the reaction picker as its sheet
/// draws it. A system menu cannot be drawn into an image, so the long-press
/// menus are tested in `ReactionMenuTests`.
///
/// The row is the iOS `TimelineRowContent` that a cell draws, on its non-SDK
/// path (an SDK item cannot be built in a test). Both paths draw the chips
/// with the same shared view.
///
/// The references hold for one simulator runtime and device
/// (`SnapshotRuntime`, in `ThreadSnapshotTests.swift`). Another runtime, as
/// on CI, skips these tests. To record again: delete
/// `__Snapshots__/ReactionSnapshotTests`, run the tests one time (they
/// record and fail), then run them again.
@MainActor
final class ReactionSnapshotTests: XCTestCase {
    private static let own = "@me:example.org"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(SnapshotRuntime.matchesReferences, SnapshotRuntime.skipReason)
    }

    // MARK: Chips on a row

    func testChipsOnRowLight() {
        assertSnapshot(of: reactedRow(), as: image(.light), named: "light")
    }

    func testChipsOnRowDark() {
        assertSnapshot(of: reactedRow(), as: image(.dark), named: "dark")
    }

    // MARK: Who reacted

    func testPeopleCardLight() {
        assertSnapshot(of: card(), as: image(.light), named: "light")
    }

    func testPeopleCardDark() {
        assertSnapshot(of: card(), as: image(.dark), named: "dark")
    }

    /// A long list wraps inside the card's width.
    func testPeopleCardWithManyPeople() {
        let text = "Ana, Ben, You, Cy, Di, Ed, Flo, Gus, Hal and Ivy"
        assertSnapshot(of: card(text: text), as: image(.light), named: "light")
    }

    /// A custom emoji with no loader draws the generic glyph in the box of
    /// an emoji, with its shortcode before the people.
    func testPeopleCardForACustomEmoji() {
        assertSnapshot(
            of: card(key: "mxc://example.org/parrot", text: ":partyparrot: · Ana and You"),
            as: image(.light),
            named: "light"
        )
    }

    // MARK: Picker sheet

    func testPickerSheetLight() {
        assertSnapshot(of: picker(), as: image(.light), named: "light")
    }

    func testPickerSheetDark() {
        assertSnapshot(of: picker(), as: image(.dark), named: "dark")
    }

    // MARK: - Views

    private func reactedRow() -> some View {
        let event = ReactedEvent(reactionPills: [
            pill("👍", ["@ana:example.org", Self.own]),
            pill("🎉", ["@ana:example.org", "@ben:example.org", "@cy:example.org"]),
            pill("mxc://example.org/parrot", ["@ben:example.org"]),
        ])
        return TimelineRowContent(
            row: event.row,
            showsSenderHeader: true,
            context: TimelineRowContext(
                timeline: nil,
                imageLoader: nil,
                ownUserId: Self.own,
                showsReadReceipts: false,
                typography: TimelineTypography(base: 15),
                retryPagination: {}
            )
        )
        .frame(width: 390)
        .background(Color(.systemBackground))
    }

    private func card(key: String = "👍", text: String = "Ana, Ben and You") -> some View {
        UI.ReactionChipPeopleCard(key: key, text: text, imageLoader: nil)
            .background(Color(.secondarySystemBackground))
    }

    private func picker() -> some View {
        UI.ReactionPickerView(catalog: .bundled, recents: ["😂", "🔥", "👀", "🙏"]) { _ in }
            .padding(.top, TimelineReactionPickerSheet.topPadding)
            .frame(width: 390)
            .background(Color(.systemBackground))
    }

    private func pill(_ key: String, _ senderIds: [String]) -> TimelineReactionPill {
        TimelineReactionPill(
            key: key,
            senders: senderIds.map { TimelineReactionPill.Sender(senderId: $0, date: Date(timeIntervalSince1970: 0)) }
        )
    }

    /// A fixed light or dark appearance, so the image does not follow the
    /// simulator's.
    private func image<Content: View>(_ style: UIUserInterfaceStyle) -> Snapshotting<Content, UIImage> {
        .image(layout: .sizeThatFits, traits: UITraitCollection(userInterfaceStyle: style))
    }
}

/// A message with fixed reactions, sender, time, and body.
private struct ReactedEvent: TimelineTextEvent {
    let reactionPills: [TimelineReactionPill]

    var body: String { "The deploy is green again." }
    var formattedBody: String? { nil }
    var media: TimelineMedia? { nil }
    var quotedReply: ComposerReply? { nil }

    var isRemote: Bool { true }
    var sender: String { "@ben:example.org" }
    var senderProfileDetails: ProfileDetails { .ready(displayName: "Ben", displayNameAmbiguous: false, avatarUrl: nil) }
    var isOwn: Bool { false }
    var isEditable: Bool { false }
    var date: Date {
        let components = DateComponents(year: 2026, month: 11, day: 26, hour: 9, minute: 15)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    var sendState: LocalSendState? { nil }
    var localCreatedAt: UInt64? { nil }
    var userReadReceipts: [String: Receipt] { [:] }
    var canBeRepliedTo: Bool { true }
    var userId: String { "@ben:example.org" }
    var displayName: String? { "Ben" }
    var avatarUrl: String? { nil }

    var row: TimelineRow {
        .message(
            uniqueId: "$reacted",
            event: self,
            kind: .text,
            heightFingerprint: TimelineRowHeightFingerprint(
                body: MessageBodyGeometry(variant: "text", text: body),
                senderName: "Ben",
                reactions: ReactionStripGeometry(
                    reactions: reactionPills.lazy.map { (key: $0.key, senderCount: $0.senders.count) },
                    hasReadReceipts: false
                )
            )
        )
    }
}
