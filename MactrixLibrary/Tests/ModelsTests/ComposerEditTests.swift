import Models
import Testing

/// MATRIX-109 (M2-B2): the composer's edit-mode rules.
struct ComposerEditTests {
    private static let alice = MentionTarget(userId: "@alice:example.org", displayName: "Alice")
    private static let alicePill = "[Alice](https://matrix.to/#/@alice:example.org)"

    // MARK: - Up arrow

    @Test func upArrowStartsAnEditOnlyInAnEmptyComposer() {
        #expect(ComposerEdit.startsEditOnUpArrow(draftText: "", attachmentCount: 0, isEditing: false))
        #expect(!ComposerEdit.startsEditOnUpArrow(draftText: "a", attachmentCount: 0, isEditing: false))
        #expect(!ComposerEdit.startsEditOnUpArrow(draftText: " ", attachmentCount: 0, isEditing: false))
        #expect(!ComposerEdit.startsEditOnUpArrow(draftText: "", attachmentCount: 1, isEditing: false))
        #expect(!ComposerEdit.startsEditOnUpArrow(draftText: "", attachmentCount: 0, isEditing: true))
    }

    // MARK: - Preview

    @Test func previewShowsChipsAsNamesOnOneLine() {
        let draft = "hi " + Self.alicePill + "\nsecond line"
        #expect(ComposerEdit.previewText(fromDraftText: draft) == "hi @Alice second line")
    }

    @Test func previewOfNoTextIsEmpty() {
        #expect(ComposerEdit.previewText(fromDraftText: "").isEmpty)
    }

    // MARK: - Save

    @Test func unchangedTextSendsNothing() {
        for kind in [ComposerEditKind.message, .caption] {
            #expect(ComposerEdit.saveDecision(kind: kind, originalDraftText: "same", draftText: "same") == .finishWithoutSending)
        }
    }

    @Test func blankMessageStaysInEditMode() {
        #expect(ComposerEdit.saveDecision(kind: .message, originalDraftText: "old", draftText: "") == .keepEditing)
        #expect(ComposerEdit.saveDecision(kind: .message, originalDraftText: "old", draftText: " \n ") == .keepEditing)
    }

    @Test func messageEditBuildsTheSameContentAsASend() {
        let draft = "hey " + Self.alicePill
        let decision = ComposerEdit.saveDecision(kind: .message, originalDraftText: "hey", draftText: draft)
        #expect(decision == .send(.message(MentionMarkdown.outgoingMessage(fromDraftText: draft))))
        guard case let .send(.message(outgoing)) = decision else {
            Issue.record("expected a message edit, got \(decision)")
            return
        }
        #expect(outgoing.markdown == draft)
        #expect(outgoing.mentionedUserIds == [Self.alice.userId])
    }

    @Test func messageEditWithoutChipsHasNoMentions() {
        let decision = ComposerEdit.saveDecision(kind: .message, originalDraftText: "old", draftText: "new **text**")
        guard case let .send(.message(outgoing)) = decision else {
            Issue.record("expected a message edit, got \(decision)")
            return
        }
        #expect(outgoing.markdown == "new **text**")
        #expect(outgoing.mentionedUserIds.isEmpty)
    }

    @Test func captionEditSendsPlainTextWithMentions() {
        let draft = " look " + Self.alicePill + " "
        let decision = ComposerEdit.saveDecision(kind: .caption, originalDraftText: "", draftText: draft)
        #expect(decision == .send(.caption(text: "look @Alice", mentionedUserIds: [Self.alice.userId])))
    }

    @Test func blankCaptionRemovesTheCaption() {
        let decision = ComposerEdit.saveDecision(kind: .caption, originalDraftText: "old caption", draftText: "  ")
        #expect(decision == .send(.caption(text: nil, mentionedUserIds: [])))
    }
}
