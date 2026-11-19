import Foundation
import Models
import Testing

/// MATRIX-200: the replay of the SDK's thread-list changes, the pane states
/// from the pagination state, and the row text.
struct ThreadListTests {
    // MARK: Fixtures

    private static func message(
        _ id: String,
        sender: String = "@ana:example.org",
        name: String? = "Ana",
        isOwn: Bool = false,
        text: String = "hello"
    ) -> ThreadListMessage {
        ThreadListMessage(
            eventId: id,
            sender: ChatListSender(userId: sender, displayName: name, isOwn: isOwn),
            avatarUrl: nil,
            date: Date(timeIntervalSince1970: 1_000),
            content: .text(text)
        )
    }

    private static func entry(_ id: String, replies: Int = 1) -> ThreadListEntry {
        ThreadListEntry(root: message(id), latestReply: message("\(id)-r"), replyCount: replies)
    }

    private static func mustApply(
        _ diff: ListDiff<ThreadListEntry>,
        to list: inout [ThreadListEntry],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        if !list.apply(diff) {
            Issue.record("the change did not fit", sourceLocation: sourceLocation)
        }
    }

    private static func mustRefuse(
        _ diff: ListDiff<ThreadListEntry>,
        to list: inout [ThreadListEntry],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        if list.apply(diff) {
            Issue.record("the change fit", sourceLocation: sourceLocation)
        }
    }

    private static func ids(_ entries: [ThreadListEntry]) -> [String] {
        entries.map(\.id)
    }

    // MARK: Diffs

    @Test func insertPutsTheRowAtTheIndex() {
        var list = [Self.entry("a"), Self.entry("c")]
        Self.mustApply(.insert(index: 1, value: Self.entry("b")), to: &list)
        #expect(Self.ids(list) == ["a", "b", "c"])
    }

    @Test func insertAtTheEndAppends() {
        var list = [Self.entry("a")]
        Self.mustApply(.insert(index: 1, value: Self.entry("b")), to: &list)
        #expect(Self.ids(list) == ["a", "b"])
    }

    @Test func newThreadAtTheFront() {
        var list = [Self.entry("a")]
        Self.mustApply(.pushFront(Self.entry("new")), to: &list)
        #expect(Self.ids(list) == ["new", "a"])
    }

    /// A new reply: the SDK replaces the row with its new count.
    @Test func setUpdatesTheRow() {
        var list = [Self.entry("a", replies: 1), Self.entry("b", replies: 2)]
        Self.mustApply(.set(index: 1, value: Self.entry("b", replies: 3)), to: &list)
        #expect(list[1].replyCount == 3)
        #expect(Self.ids(list) == ["a", "b"])
    }

    /// A new reply that the SDK moves to the front: a remove, then an
    /// insert, replayed in order.
    @Test func reorderIsRemoveThenInsert() {
        var list = [Self.entry("a"), Self.entry("b"), Self.entry("c")]
        let diffs: [ListDiff<ThreadListEntry>] = [.remove(index: 2), .insert(index: 0, value: Self.entry("c", replies: 5))]
        for diff in diffs {
            Self.mustApply(diff, to: &list)
        }
        #expect(Self.ids(list) == ["c", "a", "b"])
        #expect(list[0].replyCount == 5)
    }

    @Test func resetReplacesEverything() {
        var list = [Self.entry("a"), Self.entry("b")]
        Self.mustApply(.reset([Self.entry("x")]), to: &list)
        #expect(Self.ids(list) == ["x"])
    }

    @Test func appendAddsAPage() {
        var list = [Self.entry("a")]
        Self.mustApply(.append([Self.entry("b"), Self.entry("c")]), to: &list)
        #expect(Self.ids(list) == ["a", "b", "c"])
    }

    @Test func clearPopAndTruncate() {
        var list = [Self.entry("a"), Self.entry("b"), Self.entry("c"), Self.entry("d")]
        Self.mustApply(.popFront, to: &list)
        Self.mustApply(.popBack, to: &list)
        #expect(Self.ids(list) == ["b", "c"])
        Self.mustApply(.pushBack(Self.entry("e")), to: &list)
        Self.mustApply(.truncate(length: 1), to: &list)
        #expect(Self.ids(list) == ["b"])
        Self.mustApply(.truncate(length: 4), to: &list)
        #expect(Self.ids(list) == ["b"])
        Self.mustApply(.clear, to: &list)
        #expect(list.isEmpty)
    }

    /// A change that does not fit leaves the array alone and says so, so
    /// the caller takes a snapshot instead of crashing.
    @Test func changesOutOfRangeAreRefused() {
        var list = [Self.entry("a")]
        Self.mustRefuse(.insert(index: 3, value: Self.entry("b")), to: &list)
        Self.mustRefuse(.set(index: 1, value: Self.entry("b")), to: &list)
        Self.mustRefuse(.remove(index: -1), to: &list)
        Self.mustRefuse(.truncate(length: -1), to: &list)
        #expect(Self.ids(list) == ["a"])
        var empty: [ThreadListEntry] = []
        Self.mustRefuse(.popFront, to: &empty)
        Self.mustRefuse(.popBack, to: &empty)
    }

    @Test func mapKeepsTheChange() {
        let diff: ListDiff<Int> = .insert(index: 2, value: 7)
        guard case let .insert(index, value) = diff.map(String.init) else {
            Issue.record("map changed the case")
            return
        }
        #expect(index == 2)
        #expect(value == "7")
    }

    // MARK: Pane content

    @Test func noRowsWhileTheFirstPageLoadsIsLoading() {
        #expect(ThreadListPaneContent.of(entryCount: 0, pagination: .idle(endReached: false), errorMessage: nil) == .loading)
        #expect(ThreadListPaneContent.of(entryCount: 0, pagination: .loading, errorMessage: nil) == .loading)
    }

    @Test func noRowsAtTheEndIsEmpty() {
        #expect(ThreadListPaneContent.of(entryCount: 0, pagination: .idle(endReached: true), errorMessage: nil) == .empty)
        #expect(ThreadListPaneContent.emptyText == "No threads in this room")
    }

    @Test func noRowsAndAnErrorIsFailed() {
        let content = ThreadListPaneContent.of(entryCount: 0, pagination: .idle(endReached: false), errorMessage: "offline")
        #expect(content == .failed("offline"))
    }

    @Test func rowsWithMorePagesShowTheLoadingRow() {
        #expect(ThreadListPaneContent.of(entryCount: 3, pagination: .loading, errorMessage: nil) == .list(footer: .loading))
        #expect(ThreadListPaneContent.of(entryCount: 3, pagination: .idle(endReached: false), errorMessage: nil) == .list(footer: .loading))
    }

    @Test func rowsAtTheEndShowNoFooter() {
        #expect(ThreadListPaneContent.of(entryCount: 3, pagination: .idle(endReached: true), errorMessage: nil) == .list(footer: .end))
    }

    @Test func rowsAndAnErrorShowRetryAtTheEnd() {
        let content = ThreadListPaneContent.of(entryCount: 3, pagination: .idle(endReached: false), errorMessage: "offline")
        #expect(content == .list(footer: .failed("offline")))
    }

    // MARK: Row text

    @Test func rootExcerptHasNoPrefix() {
        #expect(Self.message("a", text: "line one\nline two").excerpt == "line one line two")
        #expect(Self.message("a", isOwn: true).excerpt == "hello")
    }

    @Test func latestReplyNamesTheSender() {
        #expect(Self.message("a").prefixedExcerpt == "Ana: hello")
        #expect(Self.message("a", isOwn: true).prefixedExcerpt == "You: hello")
        #expect(Self.message("a", name: nil).prefixedExcerpt == "ana: hello")
    }

    @Test func unknownContentHasNoExcerpt() {
        let message = ThreadListMessage(
            eventId: "a",
            sender: ChatListSender(userId: "@ana:example.org", displayName: "Ana", isOwn: false),
            avatarUrl: nil,
            date: Date(timeIntervalSince1970: 0),
            content: nil
        )
        #expect(message.excerpt == nil)
        #expect(message.prefixedExcerpt == nil)
    }

    @Test func lastActivityIsTheLatestReply() {
        let root = Self.message("a")
        let reply = ThreadListMessage(
            eventId: "r",
            sender: root.sender,
            avatarUrl: nil,
            date: Date(timeIntervalSince1970: 5_000),
            content: .text("later")
        )
        #expect(ThreadListEntry(root: root, latestReply: reply, replyCount: 1).lastActivity == reply.date)
        #expect(ThreadListEntry(root: root, latestReply: nil, replyCount: 0).lastActivity == root.date)
    }
}
