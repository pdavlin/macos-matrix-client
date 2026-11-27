@testable import MactrixiOS
import MatrixRustSDK
import Models
import Tokens
import XCTest

/// MATRIX-249: the reaction entries of the iOS long-press menu. The shared
/// action model decides them: the room's three quick reactions, then "Add
/// Reaction…". A quick reaction that the account posted shows a check.
@MainActor
final class ReactionMenuTests: XCTestCase {
    private static let own = "@me:example.org"

    private func subject(content: MessageActionSubject.Content = .text, eventId: String? = "$message") -> MessageActionSubject {
        MessageActionSubject(
            content: content,
            isOwn: false,
            eventId: eventId,
            canBeRepliedTo: true,
            isPinned: false,
            copyableText: "hello"
        )
    }

    private func pill(_ key: String, _ senderIds: [String]) -> TimelineReactionPill {
        TimelineReactionPill(
            key: key,
            senders: senderIds.map { TimelineReactionPill.Sender(senderId: $0, date: Date(timeIntervalSince1970: 0)) }
        )
    }

    // MARK: - Menu entries

    /// The room's ranked keys, in their order, then the picker.
    func testMenuOffersTheRoomsQuickReactionsThenThePicker() {
        let actions = TimelineReactionMenu.actions(for: subject(), quickReactionKeys: ["😂", "🔥", "👀"])

        XCTAssertEqual(actions, [
            .toggleReaction(key: "😂"),
            .toggleReaction(key: "🔥"),
            .toggleReaction(key: "👀"),
            .openReactionPicker,
        ])
    }

    /// A custom emoji from the room's record is a quick reaction too
    /// (MATRIX-262).
    func testMenuKeepsACustomEmojiKey() {
        let actions = TimelineReactionMenu.actions(for: subject(), quickReactionKeys: ["mxc://example.org/parrot", "👍", "🎉"])

        XCTAssertEqual(actions.first, .toggleReaction(key: "mxc://example.org/parrot"))
        XCTAssertEqual(actions.count, 4)
    }

    /// The SDK toggles a reaction on a local echo by its transaction ID.
    func testLocalEchoTakesReactions() {
        let actions = TimelineReactionMenu.actions(for: subject(eventId: nil), quickReactionKeys: ["👍", "🎉", "❤️"])

        XCTAssertEqual(actions.count, 4)
    }

    func testRedactedMessageOffersNoReaction() {
        XCTAssertEqual(TimelineReactionMenu.actions(for: subject(content: .redacted), quickReactionKeys: ["👍", "🎉", "❤️"]), [])
    }

    /// The fixture's defaults: the three fixed emoji from before M2.
    func testFixtureContextUsesTheDefaultKeys() {
        let context = TimelineRowContext(
            timeline: nil,
            imageLoader: nil,
            ownUserId: Self.own,
            showsReadReceipts: false,
            typography: TimelineTypography(base: 15),
            retryPagination: {}
        )

        XCTAssertEqual(context.quickReactionKeys, MessageActionModel.defaultQuickReactionKeys)
        XCTAssertNil(context.reactionEmojiName)
    }

    // MARK: - Own reactions

    func testOwnKeysAreTheReactionsTheAccountPosted() {
        let reactions = [
            pill("👍", ["@ana:example.org", Self.own]),
            pill("🎉", ["@ana:example.org"]),
            pill("mxc://example.org/parrot", [Self.own]),
        ]

        XCTAssertEqual(
            TimelineReactionMenu.ownKeys(of: reactions, ownUserId: Self.own),
            ["👍", "mxc://example.org/parrot"]
        )
    }

    func testNoOwnKeysWithoutOwnReactions() {
        XCTAssertEqual(TimelineReactionMenu.ownKeys(of: [pill("👍", ["@ana:example.org"])], ownUserId: Self.own), [])
        XCTAssertEqual(TimelineReactionMenu.ownKeys(of: [TimelineReactionPill](), ownUserId: Self.own), [])
    }

    // MARK: - Picker sheet

    /// The sheet is identified by its message, so a second "Add Reaction…"
    /// on another message presents a new sheet.
    func testPickerRequestIsIdentifiedByItsMessage() {
        let event = TimelineReactionPickerRequest(itemId: .eventId(eventId: "$message"))
        let echo = TimelineReactionPickerRequest(itemId: .transactionId(transactionId: "txn1"))

        XCTAssertEqual(event.id, "$message")
        XCTAssertEqual(echo.id, "txn1")
    }
}
