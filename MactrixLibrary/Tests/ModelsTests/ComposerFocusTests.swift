import Foundation
@testable import Models
import Testing

/// MATRIX-188: which way of opening a chat moves the keyboard focus to its
/// composer.
struct ComposerFocusTests {
    private static let room = ChatSelection.room("!r:example.org")
    private static let merged = ChatSelection.merged("m-seth")

    // MARK: Sources

    @Test(arguments: [
        ChatOpenSource.click,
        .returnKey,
        .quickSwitcher,
        .newChat,
        .notification,
        .shortcut,
        .link,
    ])
    func openingPathsAskForFocus(source: ChatOpenSource) {
        #expect(source.asksForComposerFocus)
        let request = ComposerFocusRule.request(opening: Self.room, from: source, serial: 3)
        #expect(request == ComposerFocusRequest(chat: Self.room, serial: 3))
    }

    @Test
    func arrowKeySelectionKeepsTheFocusInTheList() {
        #expect(!ChatOpenSource.listKeyboard.asksForComposerFocus)
        #expect(ComposerFocusRule.request(opening: Self.room, from: .listKeyboard, serial: 1) == nil)
    }

    @Test
    func aSelectionChangeWithNoKnownEventKeepsTheFocus() {
        #expect(!ChatOpenSource.unknown.asksForComposerFocus)
        #expect(ComposerFocusRule.request(opening: Self.room, from: .unknown, serial: 1) == nil)
    }

    @Test
    func noChatMakesNoRequest() {
        #expect(ComposerFocusRule.request(opening: nil, from: .click, serial: 1) == nil)
    }

    // MARK: List events

    @Test
    func theListEventTellsAClickFromAnArrowKey() {
        #expect(ChatOpenSource(listSelectionEvent: .pointer) == .click)
        #expect(ChatOpenSource(listSelectionEvent: .keyboard) == .listKeyboard)
        #expect(ChatOpenSource(listSelectionEvent: .other) == .unknown)
    }

    // MARK: The composer

    @Test
    func theChatsComposerTakesTheRequest() {
        let request = ComposerFocusRequest(chat: Self.room, serial: 1)
        #expect(ComposerFocusRule.composer(of: Self.room, membership: .joined, takes: request))
    }

    @Test
    func aMergedChatsComposerTakesItsRequest() {
        let request = ComposerFocusRequest(chat: Self.merged, serial: 1)
        #expect(ComposerFocusRule.composer(of: Self.merged, membership: .joined, takes: request))
        #expect(!ComposerFocusRule.composer(of: Self.room, membership: .joined, takes: request))
    }

    @Test
    func anotherChatsComposerLeavesTheRequest() {
        let request = ComposerFocusRequest(chat: .room("!other:example.org"), serial: 1)
        #expect(!ComposerFocusRule.composer(of: Self.room, membership: .joined, takes: request))
        #expect(!ComposerFocusRule.composer(of: Self.room, membership: .joined, takes: nil))
    }

    @Test(arguments: [Membership.invited, .left, .knocked, .banned])
    func aChatThatCannotTakeAMessageKeepsTheFocus(membership: Membership) {
        let request = ComposerFocusRequest(chat: Self.room, serial: 1)
        #expect(!ComposerFocusRule.canTakeMessage(membership))
        #expect(!ComposerFocusRule.composer(of: Self.room, membership: membership, takes: request))
    }

    @Test
    func aJoinedRoomCanTakeAMessage() {
        #expect(ComposerFocusRule.canTakeMessage(.joined))
    }

    // MARK: Thread panel (MATRIX-216)

    /// "Reply in Thread": the thread panel's composer takes the focus, and
    /// the room's main composer leaves it.
    @Test
    func theThreadComposerTakesTheReplyInThreadRequest() {
        let request = ComposerFocusRule.request(replyingInThreadOf: "$root", inRoom: "!r:example.org", serial: 2)
        #expect(request == ComposerFocusRequest(chat: Self.room, threadRoot: "$root", serial: 2))
        #expect(ComposerFocusRule.composer(of: Self.room, threadRoot: "$root", membership: .joined, takes: request))
        #expect(!ComposerFocusRule.composer(of: Self.room, membership: .joined, takes: request))
        #expect(!ComposerFocusRule.composer(of: Self.room, threadRoot: "$other", membership: .joined, takes: request))
    }

    /// Opening a chat focuses its main composer, not an open thread panel's.
    @Test
    func aThreadComposerLeavesTheChatOpenRequest() {
        let request = ComposerFocusRule.request(opening: Self.room, from: .click, serial: 1)
        #expect(!ComposerFocusRule.composer(of: Self.room, threadRoot: "$root", membership: .joined, takes: request))
        #expect(ComposerFocusRule.composer(of: Self.room, membership: .joined, takes: request))
    }
}
