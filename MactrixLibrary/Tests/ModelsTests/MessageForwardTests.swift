import Foundation
import Models
import Testing

/// MATRIX-112 (M2-B5, D-4): the Forward action, the text-or-media decision,
/// and the confirmation's preview and size text.
struct MessageForwardTests {
    private static let reactions: [MessageAction] = MessageActionModel.defaultQuickReactionKeys.map { .toggleReaction(key: $0) }
    private static let react: [MessageAction] = reactions + [.openReactionPicker]
    private static let enUS = Locale(identifier: "en_US")

    private func subject(
        _ content: MessageActionSubject.Content = .text,
        isOwn: Bool = false,
        eventId: String? = "$event",
        copyableText: String? = "hello",
        isForwardable: Bool = true
    ) -> MessageActionSubject {
        MessageActionSubject(
            content: content,
            isOwn: isOwn,
            eventId: eventId,
            canBeRepliedTo: eventId != nil,
            isPinned: false,
            copyableText: copyableText,
            isForwardable: isForwardable
        )
    }

    private func actions(_ subject: MessageActionSubject?, on surface: MessageActionSurface) -> [MessageAction] {
        MessageActionModel.items(for: subject, on: surface).map(\.action)
    }

    private func item(_ action: MessageAction, _ subject: MessageActionSubject?, on surface: MessageActionSurface) -> MessageActionItem? {
        MessageActionModel.items(for: subject, on: surface).first { $0.action == action }
    }

    private func media(_ kind: MediaSendKind, caption: String? = nil, byteCount: UInt64? = nil) -> MessageForwardMedia {
        MessageForwardMedia(kind: kind, filename: "clip.mov", caption: caption, byteCount: byteCount)
    }

    // MARK: - Availability

    @Test func otherPeoplesTextOffersForwardAfterTheRespondGroup() {
        let other = subject()
        #expect(actions(other, on: .contextMenu) == [.reply] + Self.react + [.forward, .copyText, .copyLink, .pin])
        #expect(item(.forward, other, on: .contextMenu)?.isEnabled == true)
        #expect(item(.forward, other, on: .contextMenu)?.section == .modify)
    }

    @Test func ownTextOffersForwardAfterEdit() {
        let own = MessageActionSubject(
            content: .text, isOwn: true, eventId: "$event", canBeRepliedTo: true, isPinned: false,
            copyableText: "hello", isEditable: true, isForwardable: true
        )
        #expect(actions(own, on: .contextMenu) == [.reply] + Self.react + [.edit, .forward, .copyText, .copyLink, .pin])
        let entries = MessageActionMenuLayout.entries(for: MessageActionModel.items(for: own, on: .contextMenu))
        let edit = MessageActionMenuEntry.action(MessageActionItem(action: .edit, section: .modify, isEnabled: true))
        let forward = MessageActionMenuEntry.action(MessageActionItem(action: .forward, section: .modify, isEnabled: true))
        let editIndex: Int? = entries.firstIndex(of: edit)
        #expect(editIndex.map { entries[$0 + 1] } == forward)
    }

    @Test func mediaOffersForward() {
        for content: MessageActionSubject.Content in [.image, .video(isPlayingInline: false), .audio, .file] {
            #expect(item(.forward, subject(content, copyableText: nil), on: .contextMenu)?.isEnabled == true)
        }
    }

    @Test func localEchoShowsForwardDisabled() {
        let echo = subject(isOwn: true, eventId: nil)
        #expect(item(.forward, echo, on: .contextMenu)?.isEnabled == false)
        #expect(item(.forward, echo, on: .editMenu)?.isEnabled == false)
    }

    @Test func redactedMessagesNeverOfferForward() {
        let redacted = subject(.redacted, copyableText: nil)
        #expect(!actions(redacted, on: .contextMenu).contains(.forward))
        #expect(item(.forward, redacted, on: .editMenu)?.isEnabled == false)
    }

    @Test func contentThatDoesNotForwardHasNoItem() {
        let emote = subject(isForwardable: false)
        #expect(!actions(emote, on: .contextMenu).contains(.forward))
        #expect(item(.forward, emote, on: .editMenu)?.isEnabled == false)
    }

    @Test func hoverRowNeverShowsForward() {
        #expect(!actions(subject(), on: .hoverRow).contains(.forward))
        #expect(!actions(subject(isOwn: true), on: .hoverRow).contains(.forward))
    }

    @Test func editMenuListsForwardAfterEdit() {
        let list = actions(subject(), on: .editMenu)
        let editIndex: Int? = list.firstIndex(of: .edit)
        #expect(editIndex.map { list[$0 + 1] } == .forward)
        #expect(item(.forward, nil, on: .editMenu)?.isEnabled == false)
    }

    @Test func forwardIsNotAMediaAction() {
        #expect(!MessageAction.forward.isMediaAction)
    }

    // MARK: - Text or media

    @Test func textAndNoticesForwardTheirBody() {
        #expect(MessageForwardContent.decide(type: .text, body: "hi") == .text(body: "hi"))
        #expect(MessageForwardContent.decide(type: .notice, body: "build ok") == .text(body: "build ok"))
    }

    @Test func blankTextDoesNotForward() {
        #expect(MessageForwardContent.decide(type: .text, body: " \n ") == nil)
    }

    @Test func mediaForwardsItsFile() {
        let video = media(.video, caption: "look", byteCount: 10)
        #expect(MessageForwardContent.decide(type: .video, body: "", media: video) == .media(video))
        #expect(MessageForwardContent.decide(type: .file, body: "", media: nil) == nil)
    }

    @Test func otherTypesDoNotForward() {
        for type: MessageForwardSourceType in [.emote, .location, .gallery, .other] {
            #expect(MessageForwardContent.decide(type: type, body: "body", media: media(.file)) == nil)
        }
    }

    /// The body of a message this app sent is markdown with pill links. The
    /// forward keeps each pill and its `m.mentions` entry.
    @Test func outgoingTextKeepsMentionPills() {
        let body = "hey [Alice](https://matrix.to/#/@alice:example.org), see this"
        let outgoing = MessageForwardContent.outgoingText(body: body)
        #expect(outgoing.markdown == body)
        #expect(outgoing.mentionedUserIds == ["@alice:example.org"])
    }

    @Test func outgoingTextIsStableForEscapedBoundaries() {
        // The composer escaped "!" before the pill; a forward must not add
        // a second escape.
        let body = "wow\\![Bob](https://matrix.to/#/@bob:example.org)"
        #expect(MessageForwardContent.outgoingText(body: body).markdown == body)
    }

    @Test func plainTextHasNoMentions() {
        let outgoing = MessageForwardContent.outgoingText(body: "*just* text")
        #expect(outgoing.markdown == "*just* text")
        #expect(outgoing.mentionedUserIds.isEmpty)
    }

    // MARK: - Preview

    @Test func sizeTextUsesFileUnits() {
        #expect(MessageForwardPreview.sizeText(byteCount: 24_300_000, locale: Self.enUS) == "24.3 MB")
        #expect(MessageForwardPreview.sizeText(of: .media(media(.video, byteCount: 24_300_000)), locale: Self.enUS) == "24.3 MB")
    }

    @Test func sizeTextIsNilForTextAndUnknownSize() {
        #expect(MessageForwardPreview.sizeText(of: .text(body: "hi")) == nil)
        #expect(MessageForwardPreview.sizeText(of: .media(media(.image))) == nil)
    }

    @Test func previewShowsPillsAsNames() {
        let body = "hey [Alice](https://matrix.to/#/@alice:example.org)"
        #expect(MessageForwardPreview.text(of: .text(body: body)) == "hey @Alice")
    }

    @Test func previewOfMediaIsItsCaption() {
        #expect(MessageForwardPreview.text(of: .media(media(.image, caption: "  sunset  "))) == "sunset")
        #expect(MessageForwardPreview.text(of: .media(media(.image, caption: " "))) == nil)
        #expect(MessageForwardPreview.text(of: .media(media(.image))) == nil)
    }

    @Test func longPreviewIsCut() {
        let body = String(repeating: "a", count: MessageForwardPreview.maximumPreviewLength + 10)
        let preview = MessageForwardPreview.text(of: .text(body: body))
        #expect(preview?.count == MessageForwardPreview.maximumPreviewLength + 1)
        #expect(preview?.hasSuffix("…") == true)
    }
}

/// MATRIX-112: the pick, confirm, and send steps of one forward.
@MainActor
struct MessageForwardFlowTests {
    private struct SendError: LocalizedError {
        var errorDescription: String? {
            "upload refused"
        }
    }

    private typealias Flow = MessageForwardFlow<String, String>

    @Test func pickOpensTheConfirmationOnlyAfterThePickerCloses() {
        let flow = Flow()
        flow.start("$event")
        #expect(flow.picking?.request == "$event")
        flow.pick("!room")
        #expect(flow.picking == nil)
        #expect(flow.confirming == nil)
        flow.sheetDidClose()
        #expect(flow.confirming?.request == "$event")
        #expect(flow.confirming?.target == "!room")
    }

    @Test func closingThePickerWithNoPickEndsTheForward() {
        let flow = Flow()
        flow.start("$event")
        flow.dismissPicker()
        flow.sheetDidClose()
        #expect(flow.picking == nil)
        #expect(flow.confirming == nil)
        #expect(flow.failure == nil)
    }

    @Test func cancelClosesTheConfirmationWithNoSend() async {
        let flow = Flow()
        flow.start("$event")
        flow.pick("!room")
        flow.sheetDidClose()
        flow.cancel()
        #expect(flow.confirming == nil)
        var sent = false
        await flow.confirm { _, _ in sent = true }
        #expect(!sent)
    }

    @Test func confirmSendsOnceAndCloses() async {
        let flow = Flow()
        flow.start("$event")
        flow.pick("!room")
        flow.sheetDidClose()
        var sends: [String] = []
        await flow.confirm { request, target in sends.append("\(request)->\(target)") }
        #expect(sends == ["$event->!room"])
        #expect(flow.confirming == nil)
        #expect(!flow.isSending)
        #expect(flow.failure == nil)
    }

    @Test func aFailedSendShowsItsErrorAfterTheSheetCloses() async {
        let flow = Flow()
        flow.start("$event")
        flow.pick("!room")
        flow.sheetDidClose()
        await flow.confirm { _, _ in throw SendError() }
        #expect(flow.confirming == nil)
        #expect(flow.failure == nil)
        flow.sheetDidClose()
        #expect(flow.failure == "upload refused")
        flow.clearFailure()
        #expect(flow.failure == nil)
    }

    @Test func aFailedPickShowsItsErrorAfterThePickerCloses() {
        let flow = Flow()
        flow.start("$event")
        flow.fail("no room")
        #expect(flow.picking == nil)
        #expect(flow.failure == nil)
        flow.sheetDidClose()
        #expect(flow.failure == "no room")
        #expect(flow.confirming == nil)
    }

    @Test func aNewStartDropsAnUnconfirmedForward() {
        let flow = Flow()
        flow.start("$one")
        flow.pick("!room")
        flow.sheetDidClose()
        flow.start("$two")
        #expect(flow.confirming == nil)
        #expect(flow.picking?.request == "$two")
    }
}
