import Models
import Testing

/// MATRIX-109 (M2-B2): the Edit action in the shared message-action model.
struct MessageActionEditTests {
    private static let reactions: [MessageAction] = MessageActionModel.defaultQuickReactionKeys.map { .toggleReaction(key: $0) }
    /// The quick reactions and the picker, as the menus list them.
    private static let react: [MessageAction] = reactions + [.openReactionPicker]

    private func subject(
        _ content: MessageActionSubject.Content = .text,
        isOwn: Bool = false,
        eventId: String? = "$event",
        canBeRepliedTo: Bool = true,
        copyableText: String? = "hello",
        isEditable: Bool = false
    ) -> MessageActionSubject {
        MessageActionSubject(
            content: content,
            isOwn: isOwn,
            eventId: eventId,
            canBeRepliedTo: canBeRepliedTo,
            isPinned: false,
            copyableText: copyableText,
            isEditable: isEditable
        )
    }

    private func actions(_ subject: MessageActionSubject?, on surface: MessageActionSurface) -> [MessageAction] {
        MessageActionModel.items(for: subject, on: surface).map(\.action)
    }

    private func disabled(_ subject: MessageActionSubject?, on surface: MessageActionSurface) -> [MessageAction] {
        MessageActionModel.items(for: subject, on: surface).filter { !$0.isEnabled }.map(\.action)
    }

    @Test func ownEditableTextOffersEditInItsOwnSection() {
        let own = subject(isOwn: true, isEditable: true)
        #expect(actions(own, on: .contextMenu) == [.reply] + Self.react + [.edit, .copyText, .copyLink, .pin])
        let items = MessageActionModel.items(for: own, on: .contextMenu)
        #expect(items.first { $0.action == .edit }?.section == .modify)
        let entries = MessageActionMenuLayout.entries(for: items)
        let edit = MessageActionMenuEntry.action(MessageActionItem(action: .edit, section: .modify, isEnabled: true))
        let editIndex: Int? = entries.firstIndex(of: edit)
        #expect(editIndex.map { entries[$0 - 1] } == .separator)
        #expect(editIndex.map { entries[$0 + 1] } == .separator)
    }

    @Test func otherPeoplesMessagesNeverOfferEdit() {
        let other = subject(isOwn: false, isEditable: true)
        #expect(!actions(other, on: .contextMenu).contains(.edit))
        #expect(!actions(other, on: .hoverRow).contains(.edit))
        #expect(disabled(other, on: .editMenu).contains(.edit))
    }

    @Test func ownMessageTheSDKCannotEditHasNoEdit() {
        let own = subject(isOwn: true, isEditable: false)
        #expect(!actions(own, on: .contextMenu).contains(.edit))
        #expect(!actions(own, on: .hoverRow).contains(.edit))
        #expect(disabled(own, on: .editMenu).contains(.edit))
    }

    @Test func ownEditableLocalEchoOffersEdit() {
        // The SDK edits a local echo through its transaction ID.
        let echo = subject(isOwn: true, eventId: nil, canBeRepliedTo: false, isEditable: true)
        #expect(actions(echo, on: .contextMenu).contains(.edit))
        #expect(!disabled(echo, on: .contextMenu).contains(.edit))
        #expect(actions(echo, on: .hoverRow).contains(.edit))
        #expect(!disabled(echo, on: .editMenu).contains(.edit))
    }

    @Test func redactedMessageHasNoEdit() {
        let redacted = subject(.redacted, isOwn: true, copyableText: nil, isEditable: true)
        #expect(!actions(redacted, on: .contextMenu).contains(.edit))
        #expect(disabled(redacted, on: .editMenu).contains(.edit))
    }

    @Test func ownMediaOffersCaptionEditBeforeTheMediaActions() {
        let image = subject(.image, isOwn: true, copyableText: nil, isEditable: true)
        #expect(actions(image, on: .contextMenu) == [.reply] + Self.react + [.edit, .quickLook, .saveToDownloads, .copyLink, .pin])
    }

    @Test func hoverRowShowsEditBeforePin() {
        let own = subject(isOwn: true, isEditable: true)
        #expect(actions(own, on: .hoverRow) == Self.reactions + [.openReactionPicker, .reply, .replyInThread, .edit, .pin])
    }

    @Test func editMenuEnablesEditForOwnEditableMessages() {
        let own = subject(isOwn: true, isEditable: true)
        #expect(!disabled(own, on: .editMenu).contains(.edit))
        #expect(MessageActionModel.items(for: nil, on: .editMenu).first { $0.action == .edit }?.isEnabled == false)
    }

    @Test func editIsNotAMediaAction() {
        #expect(!MessageAction.edit.isMediaAction)
        #expect(!MessageAction.edit.isQuickReaction)
    }
}
