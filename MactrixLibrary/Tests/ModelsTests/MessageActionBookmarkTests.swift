import Models
import Testing

/// MATRIX-208: Bookmark and Remove Bookmark in the one action model. The
/// menus carry them; the hover row does not.
struct MessageActionBookmarkTests {
    private func subject(
        _ content: MessageActionSubject.Content = .text,
        eventId: String? = "$event",
        isBookmarked: Bool = false,
        isInMergedChat: Bool = false
    ) -> MessageActionSubject {
        MessageActionSubject(
            content: content,
            isOwn: false,
            eventId: eventId,
            canBeRepliedTo: eventId != nil,
            isPinned: false,
            copyableText: "hello",
            isInMergedChat: isInMergedChat,
            isBookmarked: isBookmarked
        )
    }

    private func items(_ subject: MessageActionSubject?, on surface: MessageActionSurface) -> [MessageActionItem] {
        MessageActionModel.items(for: subject, on: surface).filter { $0.action == .bookmark || $0.action == .removeBookmark }
    }

    @Test func contextMenuOffersBookmarkAfterPin() {
        let actions = MessageActionModel.items(for: subject(), on: .contextMenu).map(\.action)
        #expect(actions.suffix(2) == [.pin, .bookmark])
    }

    @Test func bookmarkedMessageOffersRemove() {
        #expect(items(subject(isBookmarked: true), on: .contextMenu).map(\.action) == [.removeBookmark])
        #expect(items(subject(isBookmarked: true), on: .editMenu).map(\.action) == [.removeBookmark])
    }

    @Test func localEchoShowsBookmarkDisabled() {
        let echo = items(subject(eventId: nil), on: .contextMenu)
        #expect(echo.map(\.action) == [.bookmark])
        #expect(echo.allSatisfy { !$0.isEnabled })
    }

    @Test func redactedMessageCannotBeBookmarkedButCanBeRemoved() {
        #expect(items(subject(.redacted), on: .contextMenu).isEmpty)
        let removable = items(subject(.redacted, isBookmarked: true), on: .contextMenu)
        #expect(removable.map(\.action) == [.removeBookmark])
        let isEnabled = removable.allSatisfy(\.isEnabled)
        #expect(isEnabled)
    }

    @Test func hoverRowHasNoBookmark() {
        #expect(items(subject(), on: .hoverRow).isEmpty)
        #expect(items(subject(isBookmarked: true), on: .hoverRow).isEmpty)
    }

    @Test func worksInAMergedChat() {
        #expect(items(subject(isInMergedChat: true), on: .contextMenu).map(\.action) == [.bookmark])
        let isEnabled = items(subject(isInMergedChat: true), on: .contextMenu).allSatisfy(\.isEnabled)
        #expect(isEnabled)
    }

    @Test func editMenuShowsOneItemBeforeDelete() {
        let actions = MessageActionModel.items(for: subject(), on: .editMenu).map(\.action)
        #expect(actions.suffix(3) == [.pin, .bookmark, .redact])
        #expect(items(nil, on: .editMenu).map(\.action) == [.bookmark])
    }

    @Test func bookmarkRoutesToTheEventRoomInAMergedChat() {
        #expect(MergedChatRouting.route(for: .bookmark, eventRoomId: "!a", rooms: ["!a", "!b"]) == .room("!a"))
    }
}
