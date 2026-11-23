import Foundation
import Models
import Testing

/// MATRIX-212: the Send Later content, the registry codec, the cleanup
/// rule, the errors, the local text store, and the chat-list mark.
struct ScheduledMessageTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func message(_ delayId: String, room: String = "!a:davlin.io", at offset: TimeInterval) -> ScheduledMessage {
        ScheduledMessage(delayId: delayId, roomId: room, sendAt: Self.t0.addingTimeInterval(offset))
    }

    // MARK: - Content

    @Test func contentIsPlainTextOnly() throws {
        let json = try ScheduledMessageContent(body: "Lunch at noon?").jsonString()
        #expect(json == #"{"body":"Lunch at noon?","msgtype":"m.text"}"#)
        #expect(ScheduledMessageContent.eventType == "m.room.message")
    }

    /// Quotes, backslashes, line breaks, and markup are escaped by the
    /// encoder, and come back the same.
    @Test func contentEscapesTheBody() throws {
        let body = "She said \"hi\" \\ <b>no</b>\nsecond line ✨"
        let json = try ScheduledMessageContent(body: body).jsonString()
        let decoded = try object(json)
        #expect(decoded["body"] as? String == body)
        #expect(Set(decoded.keys) == ["msgtype", "body"])
    }

    // MARK: - Plain text

    @Test func chipsBecomeAtNamesAndCountAsMentions() {
        let text = ScheduledMessageText(draftText: "hi [Alice](https://matrix.to/#/@alice:example.org), lunch?")
        #expect(text.body == "hi @Alice, lunch?")
        #expect(text.hasMention)
        #expect(!text.hasFormatting)
        #expect(text.losesFormatting)
    }

    @Test func plainTextKeepsLineBreaksAndHasNoNote() {
        let text = ScheduledMessageText(draftText: "  first line\nsecond line\n\nthird paragraph\n")
        #expect(text.body == "first line\nsecond line\n\nthird paragraph")
        #expect(!text.losesFormatting)
    }

    @Test(arguments: [
        "**bold**",
        "_italic_",
        "`code`",
        "[site](https://example.org)",
        "# Heading",
        "- one\n- two",
        "1. one\n2. two",
        "> quoted",
        "```\nblock\n```",
        "~~gone~~",
    ])
    func markdownCountsAsFormatting(draft: String) {
        #expect(ScheduledMessageText(draftText: draft).hasFormatting)
    }

    @Test(arguments: ["Lunch at noon?", "5 * 3 = 15", "see you at 6pm", "#hashtag", "a_b_c"])
    func plainTextIsNotFormatting(draft: String) {
        #expect(!ScheduledMessageText(draftText: draft).hasFormatting)
    }

    @Test func customEmojiCountsAsFormatting() {
        let text = ScheduledMessageText(draftText: "ship it :partyparrot:", hasCustomEmoji: true)
        #expect(text.body == "ship it :partyparrot:")
        #expect(text.losesFormatting)
    }

    // MARK: - Registry wire format

    @Test func eventTypeIsInTheAppNamespace() {
        #expect(ScheduledMessageDocument.eventType == "io.davlin.matrixclient.scheduled")
    }

    @Test func encodesIdsAndMillisecondTimesOnly() throws {
        let json = try ScheduledMessageDocument(messages: [message("d1", at: 0)]).jsonString()
        #expect(json == #"{"messages":[{"delay_id":"d1","room_id":"!a:davlin.io","send_at":1800000000000}],"version":1}"#)
        // No message text: an entry has exactly the three keys.
        let entries = try #require(object(json)["messages"] as? [[String: Any]])
        #expect(entries.map { Set($0.keys) } == [["delay_id", "room_id", "send_at"]])
    }

    @Test func roundTripsThroughJSON() throws {
        let original = ScheduledMessageDocument(messages: [message("d1", at: 0), message("d2", room: "!b:davlin.io", at: 60.5)])
        let read = try ScheduledMessageDocument.read(original.jsonString())
        #expect(read == .parsed(original))
    }

    @Test func keepsUnknownFieldsThroughAWrite() throws {
        let stored = #"{"future":true,"messages":[{"delay_id":"d1","room_id":"!a","send_at":1800000000000,"note":"x"}],"version":1}"#
        guard case var .parsed(document) = ScheduledMessageDocument.read(stored) else {
            Issue.record("did not parse")
            return
        }
        document.add(message("d2", at: 60))
        let written = try object(document.jsonString())
        #expect(written["future"] as? Bool == true)
        let entries = try #require(written["messages"] as? [[String: Any]])
        #expect(entries.first?["note"] as? String == "x")
        #expect(entries.count == 2)
    }

    @Test func missingFieldsReadAsVersionOneAndEmpty() {
        #expect(ScheduledMessageDocument.read("{}") == .parsed(ScheduledMessageDocument()))
        #expect(ScheduledMessageDocument.read(nil) == .empty)
        #expect(ScheduledMessageDocument.read(nil).writableBase == ScheduledMessageDocument())
    }

    /// An entry without its time does not parse: no write may drop it.
    @Test func aBrokenEntryIsUnreadableAndNotWritable() {
        let result = ScheduledMessageDocument.read(#"{"messages":[{"delay_id":"d1","room_id":"!a"}]}"#)
        guard case .unreadable = result else {
            Issue.record("expected unreadable, got \(result)")
            return
        }
        #expect(result.writableBase == nil)
        #expect(result.document.messages.isEmpty)
    }

    @Test func aNewerVersionIsShownButNotWritable() {
        let result = ScheduledMessageDocument.read(#"{"version":2,"messages":[{"delay_id":"d1","room_id":"!a","send_at":1}]}"#)
        #expect(result.document.messages.count == 1)
        #expect(result.writableBase == nil)
    }

    /// A time with sub-millisecond parts is rounded on the way in, so the
    /// written document equals its sync echo.
    @Test func roundsToMilliseconds() throws {
        let entry = ScheduledMessage(delayId: "d1", roomId: "!a", sendAt: Self.t0.addingTimeInterval(0.000_4))
        #expect(entry.sendAt == Self.t0)
        let document = ScheduledMessageDocument(messages: [entry])
        #expect(try ScheduledMessageDocument.read(document.jsonString()) == .parsed(document))
    }

    // MARK: - Registry rules

    @Test func aDelayIdIsInTheListOnce() {
        var document = ScheduledMessageDocument(messages: [message("d1", at: 0), message("d1", at: 60)])
        #expect(document.messages.count == 1)
        document.add(message("d1", at: 120))
        #expect(document.messages.map(\.sendAt) == [Self.t0])
    }

    @Test func listsARoomsMessagesEarliestFirst() {
        let document = ScheduledMessageDocument(messages: [
            message("late", at: 600),
            message("other", room: "!b", at: 0),
            message("early", at: 60),
        ])
        #expect(document.messages(inRooms: ["!a:davlin.io"]).map(\.delayId) == ["early", "late"])
        #expect(document.messages(inRooms: ["!a:davlin.io", "!b"]).map(\.delayId) == ["other", "early", "late"])
        #expect(document.roomIds == ["!a:davlin.io", "!b"])
    }

    @Test func removesByDelayId() {
        var document = ScheduledMessageDocument(messages: [message("d1", at: 0), message("d2", at: 60)])
        document.remove(delayIds: ["d1", "unknown"])
        #expect(document.messages.map(\.delayId) == ["d2"])
    }

    /// The server can send up to 30 seconds late, so an entry stays until
    /// its time plus the grace.
    @Test func anEntryLeavesAfterItsTimePlusTheGrace() {
        let document = ScheduledMessageDocument(messages: [message("d1", at: 0), message("d2", at: 600)])
        #expect(document.sentMessages(at: Self.t0.addingTimeInterval(29)).isEmpty)
        #expect(document.sentMessages(at: Self.t0.addingTimeInterval(30)).map(\.delayId) == ["d1"])
        #expect(document.nextCleanupDate == Self.t0.addingTimeInterval(30))
        #expect(ScheduledMessageDocument().nextCleanupDate == nil)
    }

    // MARK: - Errors

    @Test(arguments: ["M_DELAY_TOO_LARGE", "ORG.MATRIX.MSC4140_DELAY_TOO_LARGE"])
    func delayTooLargeCodesMap(code: String) {
        #expect(ScheduledMessageFailure.custom(errcode: code, message: "too far") == .delayTooLarge)
    }

    @Test func anUnknownCodeKeepsItsText() {
        #expect(ScheduledMessageFailure.custom(errcode: "M_WHAT", message: "") == .other("M_WHAT"))
        #expect(ScheduledMessageFailure.custom(errcode: "M_WHAT", message: "went wrong") == .other("went wrong"))
    }

    @Test func rateLimitSaysWhenToTryAgain() {
        #expect(ScheduledMessageFailure.rateLimited(retryAfter: 1.2).message.hasSuffix("Try again in 2 seconds."))
        #expect(ScheduledMessageFailure.rateLimited(retryAfter: 1).message.hasSuffix("Try again in 1 second."))
        #expect(ScheduledMessageFailure.rateLimited(retryAfter: nil).message.hasSuffix("Try again later."))
    }

    // MARK: - Local text store

    @Test func storeSavesAndLoadsItsFile() {
        let folder = FileManager.default.temporaryDirectory.appending(component: "ScheduledMessageTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(component: "previews.json")

        var store = ScheduledMessagePreviewStore(file: file)
        #expect(store.texts.isEmpty)
        store.set("first", for: "d1", sendAt: Self.t0)
        store.set("second", for: "d2", sendAt: Self.t0.addingTimeInterval(600))
        #expect(ScheduledMessagePreviewStore(file: file).texts == ["d1": "first", "d2": "second"])

        store.remove("d1")
        store.remove("unknown")
        #expect(ScheduledMessagePreviewStore(file: file).texts == ["d2": "second"])
    }

    /// A text stays until its time plus the grace, as its entry does.
    @Test func storeDropsTextsAfterTheirTime() {
        var store = ScheduledMessagePreviewStore(file: nil)
        store.set("sent", for: "d1", sendAt: Self.t0)
        store.set("later", for: "d2", sendAt: Self.t0.addingTimeInterval(600))
        store.removeExpired(at: Self.t0.addingTimeInterval(29))
        #expect(store.texts.count == 2)
        store.removeExpired(at: Self.t0.addingTimeInterval(30))
        #expect(store.texts == ["d2": "later"])
    }

    @Test func anUnreadableStoreFileStartsEmpty() throws {
        let folder = FileManager.default.temporaryDirectory.appending(component: "ScheduledMessageTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(component: "previews.json")
        try Data("not json".utf8).write(to: file)
        #expect(ScheduledMessagePreviewStore(file: file).texts.isEmpty)
    }

    // MARK: - Chat list

    @Test func marksTheChatsWithScheduledMessages() {
        let entries = ["!a", "!b", "!c"].map { ChatListItem.room(ChatListEntry(row: ChatListRowModel(id: $0, title: $0))) }
        let visible = VisibleChatList(favorites: [entries[0]], list: [entries[1], entries[2]])
            .withScheduledMarks(roomIds: ["!a", "!c"])
        #expect(visible.favorites.map(\.row.hasScheduledMessages) == [true])
        #expect(visible.list.map(\.row.hasScheduledMessages) == [false, true])
        #expect(visible.list[1].row.accessibilityLabel.hasSuffix("has scheduled messages"))
    }

    // MARK: - Key

    private func isSendLaterKey(
        returnKey: Bool = true,
        markedText: Bool = false,
        command: Bool = true,
        option: Bool = true,
        other: Bool = false
    ) -> Bool {
        ComposerKeyDecision.isSendLaterKey(
            isReturnKey: returnKey,
            hasMarkedText: markedText,
            command: command,
            option: option,
            otherModifiers: other
        )
    }

    @Test func optionCommandReturnIsSendLater() {
        #expect(isSendLaterKey())
        #expect(!isSendLaterKey(option: false))
        #expect(!isSendLaterKey(command: false))
        #expect(!isSendLaterKey(other: true))
        #expect(!isSendLaterKey(markedText: true))
        #expect(!isSendLaterKey(returnKey: false))
    }

    /// The send keys do not change: Option-Command-Return still passes
    /// through `action(...)`.
    @Test(arguments: ComposerKeyDecision.SendMode.allCases)
    func sendLaterKeyIsNotASendKey(mode: ComposerKeyDecision.SendMode) {
        let action = ComposerKeyDecision.action(
            isReturnKey: true,
            hasMarkedText: false,
            shift: false,
            command: true,
            otherModifiers: true,
            mode: mode
        )
        #expect(action == .passthrough)
    }
}
