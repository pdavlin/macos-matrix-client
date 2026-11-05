import Foundation
import Models
import Testing

/// MATRIX-113 (M2-B6, D-2): ⌘C on a message selection copies a plain-text
/// transcript, one line per message: "Sender, HH:MM: body".
struct MessageTranscriptTests {
    private let utc = TimeZone(identifier: "UTC")!

    /// 2026-11-04 at `hour`:`minute` UTC.
    private func date(_ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 4
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: components)!
    }

    private func line(
        _ displayIndex: Int,
        _ body: MessageTranscriptLine.Body,
        sender: String = "Alice",
        at time: (Int, Int) = (9, 5)
    ) -> MessageTranscriptLine {
        MessageTranscriptLine(displayIndex: displayIndex, sender: sender, date: date(time.0, time.1), body: body)
    }

    @Test func oneLinePerMessageInTheDecidedFormat() {
        let text = MessageTranscript.text(for: [line(0, .text("hello"))], timeZone: utc)
        #expect(text == "Alice, 09:05: hello")
    }

    @Test func linesReadOldestFirstWhateverTheInputOrder() {
        // Display index 0 is the newest message, so the highest index is first.
        let lines = [
            line(0, .text("third"), sender: "Carol", at: (11, 0)),
            line(7, .text("first"), at: (9, 0)),
            line(3, .text("second"), sender: "Bob", at: (10, 30))
        ]
        let text = MessageTranscript.text(for: lines, timeZone: utc)
        #expect(text == "Alice, 09:00: first\nBob, 10:30: second\nCarol, 11:00: third")
    }

    @Test func timeIsTheTwentyFourHourClockInTheGivenZone() throws {
        let evening = line(0, .text("late"), at: (21, 7))
        #expect(MessageTranscript.text(for: [evening], timeZone: utc) == "Alice, 21:07: late")

        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        #expect(MessageTranscript.text(for: [evening], timeZone: berlin) == "Alice, 22:07: late")
    }

    @Test func multiLineBodiesKeepTheirLineBreaks() {
        let text = MessageTranscript.text(for: [line(0, .text("one\ntwo"))], timeZone: utc)
        #expect(text == "Alice, 09:05: one\ntwo")
    }

    @Test func noSelectionGivesAnEmptyTranscript() {
        #expect(MessageTranscript.text(for: [], timeZone: utc).isEmpty)
    }

    @Test func mediaShowsKindAndFilenameThenTheCaption() {
        #expect(MessageTranscript.bodyText(of: .media(.image, filename: "photo.jpg", caption: nil)) == "[Image: photo.jpg]")
        #expect(MessageTranscript.bodyText(of: .media(.video, filename: "clip.mp4", caption: "")) == "[Video: clip.mp4]")
        #expect(MessageTranscript.bodyText(of: .media(.audio, filename: "note.m4a", caption: "listen")) == "[Audio: note.m4a] listen")
        #expect(MessageTranscript.bodyText(of: .media(.file, filename: "", caption: nil)) == "[File]")
    }

    @Test func messagesWithoutTextGetPlaceholders() {
        #expect(MessageTranscript.bodyText(of: .redacted) == "[Message deleted]")
        #expect(MessageTranscript.bodyText(of: .unableToDecrypt) == "[Unable to decrypt]")
        #expect(MessageTranscript.bodyText(of: .unsupported) == "[Unsupported message]")
        #expect(MessageTranscript.bodyText(of: .sticker("wave")) == "[Sticker: wave]")
        #expect(MessageTranscript.bodyText(of: .poll(question: "Lunch?")) == "[Poll: Lunch?]")
        #expect(MessageTranscript.bodyText(of: .gallery("trip")) == "[Gallery: trip]")
    }

    @Test func senderIsTheDisplayNameElseTheUserId() {
        let named = ProfileDetails.ready(displayName: "Alice", displayNameAmbiguous: false, avatarUrl: nil)
        #expect(MessageTranscriptLine.senderName(userId: "@alice:hs", profile: named) == "Alice")

        let blank = ProfileDetails.ready(displayName: "  ", displayNameAmbiguous: false, avatarUrl: nil)
        #expect(MessageTranscriptLine.senderName(userId: "@alice:hs", profile: blank) == "@alice:hs")

        let unnamed = ProfileDetails.ready(displayName: nil, displayNameAmbiguous: false, avatarUrl: nil)
        #expect(MessageTranscriptLine.senderName(userId: "@alice:hs", profile: unnamed) == "@alice:hs")
        #expect(MessageTranscriptLine.senderName(userId: "@alice:hs", profile: .pending) == "@alice:hs")
    }
}
