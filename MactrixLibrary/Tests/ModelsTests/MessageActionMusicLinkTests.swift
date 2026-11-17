import Models
import Testing

/// MATRIX-178: "Open Original Link" and "Copy Original Link" in the message
/// context menu, for a message with a marked music link.
struct MessageActionMusicLinkTests {
    private static let original = "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=abc"

    private func subject(_ content: MessageActionSubject.Content = .text, originalMusicLink: String?) -> MessageActionSubject {
        MessageActionSubject(
            content: content,
            isOwn: false,
            eventId: "$event",
            canBeRepliedTo: true,
            isPinned: false,
            copyableText: "listen",
            originalMusicLink: originalMusicLink
        )
    }

    private func actions(_ subject: MessageActionSubject, on surface: MessageActionSurface) -> [MessageAction] {
        MessageActionModel.items(for: subject, on: surface).map(\.action)
    }

    @Test func aMarkedLinkAddsTheTwoItemsAfterCopyLink() {
        let menu = actions(subject(originalMusicLink: Self.original), on: .contextMenu)
        let copyLink = menu.firstIndex(of: .copyLink)
        #expect(copyLink.map { Array(menu[($0 + 1)...].prefix(2)) } == [.openOriginalLink, .copyOriginalLink])
        let items = MessageActionModel.items(for: subject(originalMusicLink: Self.original), on: .contextMenu)
        let added = items.filter { [.openOriginalLink, .copyOriginalLink].contains($0.action) }
        let allEnabled = added.allSatisfy(\.isEnabled)
        #expect(added.count == 2)
        #expect(allEnabled)
    }

    @Test func noMarkedLinkNoItems() {
        let menu = actions(subject(originalMusicLink: nil), on: .contextMenu)
        #expect(!menu.contains(.openOriginalLink))
        #expect(!menu.contains(.copyOriginalLink))
    }

    @Test func theHoverRowAndTheEditMenuDoNotShowThem() {
        for surface in [MessageActionSurface.hoverRow, .editMenu] {
            let list = actions(subject(originalMusicLink: Self.original), on: surface)
            #expect(!list.contains(.openOriginalLink))
            #expect(!list.contains(.copyOriginalLink))
        }
    }

    @Test func theyNeedNoRoom() {
        for action in [MessageAction.openOriginalLink, .copyOriginalLink] {
            #expect(!action.needsRoomView)
            #expect(!action.isMediaAction)
            #expect(MergedChatRouting.route(for: action, eventRoomId: "!a", rooms: ["!a"]) == .noRoom)
        }
    }
}
