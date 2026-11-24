@testable import Core
import Models
import Testing

/// MATRIX-235: File > Archive Chat (⌘E) acts on the chat the window selects
/// when the item runs, not on the chat it selected when the command was
/// made. SwiftUI keeps the old command while each new one is equal to it.
@MainActor
struct InboxCommandTests {
    /// The inbox of the tests: the archived rooms, the actions that ran, and
    /// the chat that opens after an archive of the open chat (MATRIX-222).
    @MainActor
    final class Inbox {
        var archived: Set<String> = []
        var actions: [String] = []
        var nextChat: [ChatSelection: ChatSelection] = [:]

        func target(in windowState: WindowState) -> InboxCommand.Target? {
            guard let selection = windowState.chatSelection, let roomId = selection.roomId else { return nil }
            return InboxCommand.Target(selection: selection, roomIds: [roomId], isArchived: archived.contains(roomId))
        }

        /// Reads the state of the rooms when it runs, as
        /// `SidebarInbox.toggleArchive` does.
        func toggle(_ target: InboxCommand.Target, in windowState: WindowState) {
            guard let roomId = target.roomIds.first else { return }
            if archived.contains(roomId) {
                archived.remove(roomId)
                actions.append("unarchive \(roomId)")
            } else {
                archived.insert(roomId)
                actions.append("archive \(roomId)")
                if let next = nextChat[target.selection] {
                    windowState.chatSelection = next
                }
            }
        }

        func command(in windowState: WindowState) -> InboxCommand? {
            InboxCommand(
                windowState: windowState,
                target: { self.target(in: $0) },
                perform: { self.toggle($0, in: $1) }
            )
        }
    }

    @Test
    func theCommandActsOnTheChatSelectedWhenItRuns() throws {
        let inbox = Inbox()
        let window = WindowState()
        window.chatSelection = .room("!familyphotos")
        let command = try #require(inbox.command(in: window))

        window.chatSelection = .room("!racecar")
        // The command for #racecar is equal, so SwiftUI keeps the first one.
        #expect(inbox.command(in: window) == command)
        command.toggle()

        #expect(inbox.actions == ["archive !racecar"])
        #expect(inbox.archived == ["!racecar"])
    }

    /// MATRIX-222: ⌘E archives the open chat and opens the next one. The
    /// next ⌘E archives that chat; it does not unarchive the first.
    @Test
    func aSecondArchiveActsOnTheChatThatOpened() throws {
        let inbox = Inbox()
        inbox.nextChat = [.room("!familyphotos"): .room("!racecar")]
        let window = WindowState()
        window.chatSelection = .room("!familyphotos")
        let command = try #require(inbox.command(in: window))

        command.toggle()
        #expect(window.chatSelection == .room("!racecar"))
        #expect(inbox.command(in: window) == command)
        command.toggle()

        #expect(inbox.actions == ["archive !familyphotos", "archive !racecar"])
        #expect(inbox.archived == ["!familyphotos", "!racecar"])
    }

    @Test
    func theTitleFollowsTheSelection() throws {
        let inbox = Inbox()
        inbox.archived = ["!a"]
        let window = WindowState()
        window.chatSelection = .room("!a")
        let archived = try #require(inbox.command(in: window))
        #expect(archived.isArchived)

        window.chatSelection = .room("!b")
        let inInbox = try #require(inbox.command(in: window))
        #expect(!inInbox.isArchived)
        #expect(archived != inInbox)
    }

    /// Each window has its own command, so the key window's command
    /// replaces the other window's one.
    @Test
    func commandsOfTwoWindowsAreNotEqual() throws {
        let inbox = Inbox()
        let first = WindowState()
        let second = WindowState()
        first.chatSelection = .room("!a")
        second.chatSelection = .room("!b")
        let firstCommand = try #require(inbox.command(in: first))
        let secondCommand = try #require(inbox.command(in: second))
        #expect(firstCommand != secondCommand)

        secondCommand.toggle()
        #expect(inbox.actions == ["archive !b"])
    }

    @Test
    func noChatMeansNoCommandAndNoAction() throws {
        let inbox = Inbox()
        let window = WindowState()
        #expect(inbox.command(in: window) == nil)

        window.chatSelection = .room("!a")
        let command = try #require(inbox.command(in: window))
        window.chatSelection = nil
        command.toggle()
        #expect(inbox.actions.isEmpty)
    }
}
