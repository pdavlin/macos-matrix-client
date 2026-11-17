@testable import Core
import Models
import Testing

/// MATRIX-188: the window's composer focus request.
@MainActor
struct WindowStateComposerFocusTests {
    private static let room = ChatSelection.room("!r:example.org")
    private static let other = ChatSelection.room("!o:example.org")

    @Test
    func aClickSelectsTheChatAndAsksForFocus() {
        let state = WindowState()
        state.open(Self.room, from: .click)
        #expect(state.chatSelection == Self.room)
        #expect(state.composerFocusRequest?.chat == Self.room)
        #expect(state.takeComposerFocusRequest(composerChat: Self.room, membership: .joined))
        #expect(state.composerFocusRequest == nil)
        // A request is taken once.
        #expect(!state.takeComposerFocusRequest(composerChat: Self.room, membership: .joined))
    }

    @Test
    func anArrowKeySelectsTheChatAndDropsAnOlderRequest() {
        let state = WindowState()
        state.open(Self.room, from: .notification)
        state.open(Self.other, from: .listKeyboard)
        #expect(state.chatSelection == Self.other)
        #expect(state.composerFocusRequest == nil)
        #expect(!state.takeComposerFocusRequest(composerChat: Self.room, membership: .joined))
    }

    @Test
    func returnAsksForFocusOnTheSelectedChat() {
        let state = WindowState()
        state.open(Self.room, from: .listKeyboard)
        #expect(state.requestComposerFocus(from: .returnKey))
        #expect(state.composerFocusRequest?.chat == Self.room)
    }

    @Test
    func returnWithNoSelectionAsksForNothing() {
        let state = WindowState()
        #expect(!state.requestComposerFocus(from: .returnKey))
        #expect(state.composerFocusRequest == nil)
    }

    @Test
    func aSecondRequestForTheSameChatIsANewValue() {
        let state = WindowState()
        state.open(Self.room, from: .click)
        let first = state.composerFocusRequest
        state.requestComposerFocus(from: .returnKey)
        #expect(state.composerFocusRequest != first)
    }

    @Test
    func aChatThatCannotTakeAMessageLeavesTheRequest() {
        let state = WindowState()
        state.open(Self.room, from: .shortcut)
        #expect(!state.takeComposerFocusRequest(composerChat: Self.room, membership: .left))
        #expect(state.composerFocusRequest?.chat == Self.room)
    }
}
