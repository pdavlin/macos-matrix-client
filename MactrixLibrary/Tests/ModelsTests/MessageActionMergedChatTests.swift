import Models
import Testing

/// MATRIX-149: a merged chat has no thread view and no pin list, so one rule
/// in the action model takes Reply in Thread, Pin, and Unpin off every
/// surface there.
struct MessageActionMergedChatTests {
    private static let reactions: [MessageAction] = MessageActionModel.defaultQuickReactionKeys.map { .toggleReaction(key: $0) }

    private func subject(isPinned: Bool = false, isInMergedChat: Bool) -> MessageActionSubject {
        MessageActionSubject(
            content: .text,
            isOwn: false,
            eventId: "$event",
            canBeRepliedTo: true,
            isPinned: isPinned,
            copyableText: "hello",
            isInMergedChat: isInMergedChat
        )
    }

    private func actions(_ subject: MessageActionSubject, on surface: MessageActionSurface) -> [MessageAction] {
        MessageActionModel.items(for: subject, on: surface).map(\.action)
    }

    private func disabled(_ subject: MessageActionSubject, on surface: MessageActionSurface) -> [MessageAction] {
        MessageActionModel.items(for: subject, on: surface).filter { !$0.isEnabled }.map(\.action)
    }

    /// The hover row and the right-click menu leave the actions out.
    @Test func hoverRowAndContextMenuLeaveOutThreadAndPinActions() {
        let merged = subject(isInMergedChat: true)
        #expect(actions(merged, on: .hoverRow) == Self.reactions + [.openReactionPicker, .reply])
        #expect(actions(merged, on: .contextMenu) == [.reply] + Self.reactions + [.openReactionPicker, .copyText, .copyLink])

        let pinned = subject(isPinned: true, isInMergedChat: true)
        #expect(!actions(pinned, on: .hoverRow).contains(.unpin))
        #expect(!actions(pinned, on: .contextMenu).contains(.unpin))
    }

    /// The Edit menu keeps its list, so items do not jump, and shows Pin or
    /// Unpin disabled.
    @Test func editMenuKeepsItsListWithPinDisabled() {
        let merged = subject(isInMergedChat: true)
        let room = subject(isInMergedChat: false)
        #expect(actions(merged, on: .editMenu) == actions(room, on: .editMenu))
        #expect(disabled(room, on: .editMenu) == [.edit, .forward, .redact])
        #expect(disabled(merged, on: .editMenu) == [.edit, .forward, .pin, .redact])
        #expect(disabled(subject(isPinned: true, isInMergedChat: true), on: .editMenu).contains(.unpin))
    }

    /// The rule changes nothing for a room, and a room is the default.
    @Test func roomKeepsThreadAndPinActions() {
        let room = subject(isInMergedChat: false)
        #expect(actions(room, on: .hoverRow) == Self.reactions + [.openReactionPicker, .reply, .replyInThread, .pin])
        #expect(actions(room, on: .contextMenu).contains(.pin))
        let byDefault = MessageActionSubject(
            content: .text, isOwn: false, eventId: "$event", canBeRepliedTo: true, isPinned: false, copyableText: "hello"
        )
        #expect(byDefault == room)
    }
}
