import Models
import Testing

/// MATRIX-108 (M2-B1): one action model drives the right-click menu, the
/// hover row, and the Edit menu.
struct MessageActionModelTests {
    private static let reactions: [MessageAction] = MessageActionModel.quickReactionKeys.map { .toggleReaction(key: $0) }

    private func subject(
        _ content: MessageActionSubject.Content = .text,
        isOwn: Bool = false,
        eventId: String? = "$event",
        canBeRepliedTo: Bool = true,
        isPinned: Bool = false,
        copyableText: String? = "hello",
        redactPermission: MessageRedactPermission = .none
    ) -> MessageActionSubject {
        MessageActionSubject(
            content: content,
            isOwn: isOwn,
            eventId: eventId,
            canBeRepliedTo: canBeRepliedTo,
            isPinned: isPinned,
            copyableText: copyableText,
            redactPermission: redactPermission
        )
    }

    /// A member who may redact own messages only: the common room default.
    private static let member = MessageRedactPermission(canRedactOwn: true, canRedactOther: false)
    /// A moderator who may redact anyone's messages.
    private static let moderator = MessageRedactPermission(canRedactOwn: true, canRedactOther: true)

    private func actions(_ subject: MessageActionSubject?, on surface: MessageActionSurface) -> [MessageAction] {
        MessageActionModel.items(for: subject, on: surface).map(\.action)
    }

    private func disabled(_ subject: MessageActionSubject?, on surface: MessageActionSurface) -> [MessageAction] {
        MessageActionModel.items(for: subject, on: surface).filter { !$0.isEnabled }.map(\.action)
    }

    // MARK: - Context menu

    @Test func textMessageGetsAContextMenu() {
        #expect(actions(subject(), on: .contextMenu) == [.reply] + Self.reactions + [.copyText, .copyLink, .pin])
        #expect(disabled(subject(), on: .contextMenu).isEmpty)
    }

    @Test func withoutRedactPermissionOwnAndOtherTextOfferTheSameActions() {
        // `.none` is the value before the power levels load.
        #expect(actions(subject(isOwn: true), on: .contextMenu) == actions(subject(isOwn: false), on: .contextMenu))
    }

    @Test func imageKeepsQuickLookAndSave() {
        let image = subject(.image, copyableText: nil)
        #expect(actions(image, on: .contextMenu) == [.reply] + Self.reactions + [.quickLook, .saveToDownloads, .copyLink, .pin])
    }

    @Test func imageCaptionIsCopyable() {
        #expect(actions(subject(.image, copyableText: "caption"), on: .contextMenu).contains(.copyText))
        #expect(!actions(subject(.image, copyableText: ""), on: .contextMenu).contains(.copyText))
    }

    @Test func videoBeforePlaybackOffersPlayInlineNotQuickLook() {
        // S-38: a click opens Quick Look, so the menu offers inline playback.
        let menu = actions(subject(.video(isPlayingInline: false), copyableText: nil), on: .contextMenu)
        #expect(menu.contains(.playInline))
        #expect(!menu.contains(.quickLook))
        #expect(menu.contains(.saveToDownloads))
    }

    @Test func videoDuringPlaybackOffersQuickLook() {
        let menu = actions(subject(.video(isPlayingInline: true), copyableText: nil), on: .contextMenu)
        #expect(menu.contains(.quickLook))
        #expect(!menu.contains(.playInline))
        #expect(menu.contains(.saveToDownloads))
    }

    @Test func audioAndFileOfferQuickLookAndSave() {
        for content in [MessageActionSubject.Content.audio, .file] {
            let menu = actions(subject(content, copyableText: nil), on: .contextMenu)
            #expect(menu.contains(.quickLook))
            #expect(menu.contains(.saveToDownloads))
            #expect(!menu.contains(.playInline))
        }
    }

    @Test func textHasNoMediaActions() {
        #expect(!actions(subject(), on: .contextMenu).contains { $0.isMediaAction })
    }

    @Test func localEchoDisablesLinkPinAndReply() {
        let echo = subject(eventId: nil, canBeRepliedTo: false)
        #expect(actions(echo, on: .contextMenu) == [.reply] + Self.reactions + [.copyText, .copyLink, .pin])
        #expect(disabled(echo, on: .contextMenu) == [.reply, .copyLink, .pin])
    }

    @Test func redactedOffersOnlyCopyLink() {
        let redacted = subject(.redacted, copyableText: nil)
        #expect(actions(redacted, on: .contextMenu) == [.copyLink])
        #expect(disabled(redacted, on: .contextMenu).isEmpty)
    }

    @Test func pinnedMessageOffersUnpin() {
        let menu = actions(subject(isPinned: true), on: .contextMenu)
        #expect(menu.contains(.unpin))
        #expect(!menu.contains(.pin))
    }

    @Test func otherContentOffersRespondAndLinkOnly() {
        // Stickers, polls, undecryptable messages: no text, no media.
        #expect(actions(subject(.other, copyableText: nil), on: .contextMenu) == [.reply] + Self.reactions + [.copyLink, .pin])
    }

    // MARK: - Hover row

    @Test func hoverRowKeepsItsPreM2Buttons() {
        #expect(actions(subject(), on: .hoverRow) == Self.reactions + [.openReactionPicker, .reply, .replyInThread, .pin])
    }

    @Test func hoverRowShowsUnpinForAPinnedMessage() {
        #expect(actions(subject(isPinned: true), on: .hoverRow).last == .unpin)
    }

    @Test func hoverRowHidesWhatCannotRunNow() {
        // A local echo keeps its reactions, as before, and loses reply,
        // thread, and pin instead of showing them dead.
        let echo = subject(eventId: nil, canBeRepliedTo: false)
        #expect(actions(echo, on: .hoverRow) == Self.reactions + [.openReactionPicker])
        #expect(disabled(echo, on: .hoverRow).isEmpty)
    }

    @Test func hoverRowIsEmptyForARedactedMessage() {
        #expect(actions(subject(.redacted, copyableText: nil), on: .hoverRow).isEmpty)
    }

    @Test func hoverRowHasNoMenuOnlyActions() {
        let hover = actions(subject(.image, copyableText: "caption"), on: .hoverRow)
        #expect(!hover.contains(.copyText))
        #expect(!hover.contains(.copyLink))
        #expect(!hover.contains { $0.isMediaAction })
    }

    // MARK: - Edit menu

    @Test func editMenuKeepsOneShapeAcrossMessages() {
        let text = actions(subject(), on: .editMenu)
        #expect(text == [.reply] + Self.reactions + [.copyText, .copyLink, .pin, .redact])
        #expect(actions(subject(.image, copyableText: nil), on: .editMenu) == text)
        #expect(actions(subject(.redacted, copyableText: nil), on: .editMenu) == text)
        #expect(actions(nil, on: .editMenu) == text)
    }

    @Test func editMenuDisablesWhatDoesNotApply() {
        #expect(disabled(subject(.image, copyableText: nil), on: .editMenu) == [.copyText, .redact])
        #expect(disabled(subject(.redacted, copyableText: nil), on: .editMenu) == [.reply] + Self.reactions + [.copyText, .pin, .redact])
    }

    @Test func editMenuWithoutATargetIsAllDisabled() {
        #expect(MessageActionModel.items(for: nil, on: .editMenu).allSatisfy { !$0.isEnabled })
    }

    @Test func editMenuSwapsPinForUnpin() {
        let pinned = subject(isOwn: true, isPinned: true, redactPermission: Self.member)
        #expect(actions(pinned, on: .editMenu).contains(.unpin))
        #expect(!actions(pinned, on: .editMenu).contains(.pin))
        #expect(disabled(pinned, on: .editMenu).isEmpty)
    }

    @Test func editMenuHasNoMediaOrHoverOnlyActions() {
        let edit = actions(subject(.video(isPlayingInline: true)), on: .editMenu)
        #expect(!edit.contains { $0.isMediaAction })
        #expect(!edit.contains(.replyInThread))
        #expect(!edit.contains(.openReactionPicker))
    }

    // MARK: - Redact (MATRIX-110, M2-B3)

    @Test func ownMessageOffersDeleteLastInItsOwnSection() {
        let own = subject(isOwn: true, redactPermission: Self.member)
        let items = MessageActionModel.items(for: own, on: .contextMenu)
        #expect(items.last == MessageActionItem(action: .redact, section: .destructive, isEnabled: true))
        let entries = MessageActionMenuLayout.entries(for: items)
        #expect(entries.suffix(2) == [.separator, .action(MessageActionItem(action: .redact, section: .destructive, isEnabled: true))])
    }

    @Test func otherPersonsMessageHasNoDeleteWithoutThePowerLevel() {
        let other = subject(isOwn: false, redactPermission: Self.member)
        #expect(!actions(other, on: .contextMenu).contains(.redact))
        #expect(disabled(other, on: .editMenu).contains(.redact))
    }

    @Test func otherPersonsMessageOffersDeleteToAModerator() {
        let other = subject(isOwn: false, redactPermission: Self.moderator)
        #expect(actions(other, on: .contextMenu).last == .redact)
        #expect(!disabled(other, on: .editMenu).contains(.redact))
    }

    @Test func ownMessageHasNoDeleteWhenThePowerLevelsForbidIt() {
        let forbidden = MessageRedactPermission(canRedactOwn: false, canRedactOther: true)
        #expect(!actions(subject(isOwn: true, redactPermission: forbidden), on: .contextMenu).contains(.redact))
    }

    @Test func noDeleteBeforeThePowerLevelsLoad() {
        for isOwn in [true, false] {
            #expect(!actions(subject(isOwn: isOwn), on: .contextMenu).contains(.redact))
        }
    }

    @Test func ownLocalEchoOffersDelete() {
        // The SDK takes the transaction ID and aborts the pending send.
        let echo = subject(isOwn: true, eventId: nil, canBeRepliedTo: false, redactPermission: Self.member)
        #expect(actions(echo, on: .contextMenu).last == .redact)
        #expect(!disabled(echo, on: .contextMenu).contains(.redact))
        #expect(!disabled(echo, on: .editMenu).contains(.redact))
    }

    @Test func redactedMessageHasNoDelete() {
        let redacted = subject(.redacted, isOwn: true, copyableText: nil, redactPermission: Self.moderator)
        #expect(actions(redacted, on: .contextMenu) == [.copyLink])
        #expect(disabled(redacted, on: .editMenu).contains(.redact))
    }

    @Test func mediaMessagesOfferDelete() {
        let media: [MessageActionSubject.Content] = [.image, .video(isPlayingInline: false), .video(isPlayingInline: true), .audio, .file]
        for content in media {
            let menu = actions(subject(content, isOwn: true, copyableText: nil, redactPermission: Self.member), on: .contextMenu)
            #expect(menu.last == .redact)
        }
    }

    @Test func otherContentOffersDeleteToItsSender() {
        // Stickers, polls, undecryptable messages can be deleted too.
        #expect(actions(subject(.other, isOwn: true, copyableText: nil, redactPermission: Self.member), on: .contextMenu).last == .redact)
    }

    @Test func hoverRowNeverOffersDelete() {
        let subjects = [
            subject(isOwn: true, redactPermission: Self.moderator),
            subject(isOwn: false, redactPermission: Self.moderator),
            subject(.image, isOwn: true, redactPermission: Self.moderator),
        ]
        for subject in subjects {
            #expect(!actions(subject, on: .hoverRow).contains(.redact))
        }
    }

    @Test func deleteIsNotAMediaAction() {
        #expect(!MessageAction.redact.isMediaAction)
        #expect(!MessageAction.redact.isQuickReaction)
    }

    @Test func blankReasonSendsNoReason() {
        #expect(MessageRedaction.normalizedReason("") == nil)
        #expect(MessageRedaction.normalizedReason("  \n\t ") == nil)
        #expect(MessageRedaction.normalizedReason("  spam \n") == "spam")
    }

    // MARK: - Shared rules

    @Test func everySurfaceListsActionsInSectionOrder() {
        let subjects = [
            subject(), subject(.image), subject(.video(isPlayingInline: true)), subject(isPinned: true), subject(eventId: nil),
            subject(isOwn: true, redactPermission: Self.member), subject(.image, isOwn: false, redactPermission: Self.moderator),
        ]
        for subject in subjects {
            for surface in MessageActionSurface.allCases {
                let sections = MessageActionModel.items(for: subject, on: surface).map(\.section)
                #expect(sections == sections.sorted())
            }
        }
    }

    @Test func subjectWithContentChangesOnlyTheContent() {
        let base = subject(.video(isPlayingInline: false), isOwn: true, isPinned: true)
        let playing = base.with(content: .video(isPlayingInline: true))
        #expect(playing.content == .video(isPlayingInline: true))
        #expect(playing.with(content: base.content) == base)
    }
}

/// The menu lines built from action items.
struct MessageActionMenuLayoutTests {
    private func items(_ subject: MessageActionSubject) -> [MessageActionItem] {
        MessageActionModel.items(for: subject, on: .contextMenu)
    }

    private func subject(_ content: MessageActionSubject.Content, copyableText: String?) -> MessageActionSubject {
        MessageActionSubject(
            content: content,
            isOwn: false,
            eventId: "$e",
            canBeRepliedTo: true,
            isPinned: false,
            copyableText: copyableText
        )
    }

    @Test func quickReactionsFoldIntoOneSubmenuWithSeparatorsBetweenSections() {
        let text = subject(.text, copyableText: "hi")
        let entries = MessageActionMenuLayout.entries(for: items(text))

        let shape = entries.map { entry -> String in
            switch entry {
            case let .action(item): "action:\(item.action)"
            case let .reactions(reactions): "reactions:\(reactions.count)"
            case .separator: "separator"
            }
        }
        #expect(shape == [
            "action:reply", "reactions:3", "separator",
            "action:copyText", "action:copyLink", "separator",
            "action:pin"
        ])
    }

    @Test func noLeadingTrailingOrDoubleSeparators() {
        let redacted = subject(.redacted, copyableText: nil)
        #expect(MessageActionMenuLayout.entries(for: items(redacted)).count == 1)
        #expect(MessageActionMenuLayout.entries(for: []).isEmpty)
    }
}
