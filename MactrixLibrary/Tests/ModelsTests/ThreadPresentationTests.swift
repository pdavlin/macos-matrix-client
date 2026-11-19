import Models
import Testing

/// MATRIX-183: the reply count text, the panel header subtitle, the
/// composer placeholder rule, and the open-thread mark rule.
struct ThreadPresentationTests {
    @Test func replyCountIsSingularForOne() {
        #expect(ThreadReplyCount.label(1) == "1 reply")
    }

    @Test(arguments: [0, 2, 4, 120])
    func replyCountIsPluralOtherwise(count: Int) {
        #expect(ThreadReplyCount.label(count) == "\(count) replies")
    }

    @Test func subtitleNamesRoomAndCount() {
        #expect(ThreadPanelHeaderText.subtitle(roomName: "#general", replyCount: 4) == "#general · 4 replies")
        #expect(ThreadPanelHeaderText.subtitle(roomName: "#general", replyCount: 1) == "#general · 1 reply")
    }

    @Test func subtitleWithoutCountIsRoomOnly() {
        #expect(ThreadPanelHeaderText.subtitle(roomName: "#general", replyCount: nil) == "#general")
    }

    @Test func subtitleWithoutRoomIsCountOnly() {
        #expect(ThreadPanelHeaderText.subtitle(roomName: nil, replyCount: 2) == "2 replies")
        #expect(ThreadPanelHeaderText.subtitle(roomName: "", replyCount: 2) == "2 replies")
    }

    @Test func subtitleWithNothingIsNil() {
        #expect(ThreadPanelHeaderText.subtitle(roomName: nil, replyCount: nil) == nil)
    }

    // MARK: Placeholder

    @Test func threadComposerRepliesInThread() {
        #expect(ComposerPlaceholder.text(isThreadTimeline: true, mergedPlaceholder: nil, roomName: "#general") == "Reply in thread…")
    }

    @Test func roomComposerNamesRoom() {
        #expect(ComposerPlaceholder.text(isThreadTimeline: false, mergedPlaceholder: nil, roomName: "#general") == "Message #general")
    }

    @Test func roomComposerWithoutNameSaysRoom() {
        #expect(ComposerPlaceholder.text(isThreadTimeline: false, mergedPlaceholder: nil, roomName: nil) == "Message room")
    }

    @Test func mergedComposerKeepsItsPlaceholder() {
        let text = ComposerPlaceholder.text(isThreadTimeline: false, mergedPlaceholder: "Message Seth", roomName: "Seth (Slack)")
        #expect(text == "Message Seth")
    }

    // MARK: Open-thread mark

    private static let panel = OpenThreadPanel(roomId: "!room:example.org", rootEventId: "$root")

    @Test func markOnTheOpenRootInTheMainColumn() {
        #expect(OpenThreadMark.isMarked(rowEventId: "$root", rowRoomId: "!room:example.org", rowTimelineIsThread: false, panel: Self.panel))
    }

    @Test func noMarkWhenThePanelIsClosed() {
        #expect(!OpenThreadMark.isMarked(rowEventId: "$root", rowRoomId: "!room:example.org", rowTimelineIsThread: false, panel: nil))
    }

    @Test func noMarkWhenThePanelShowsAnotherThread() {
        let other = OpenThreadPanel(roomId: "!room:example.org", rootEventId: "$other")
        #expect(!OpenThreadMark.isMarked(rowEventId: "$root", rowRoomId: "!room:example.org", rowTimelineIsThread: false, panel: other))
    }

    @Test func noMarkForTheSameEventIdInAnotherRoom() {
        let marked = OpenThreadMark.isMarked(
            rowEventId: "$root",
            rowRoomId: "!elsewhere:example.org",
            rowTimelineIsThread: false,
            panel: Self.panel
        )
        #expect(!marked)
    }

    @Test func noMarkInsideThePanel() {
        #expect(!OpenThreadMark.isMarked(rowEventId: "$root", rowRoomId: "!room:example.org", rowTimelineIsThread: true, panel: Self.panel))
    }

    @Test func noMarkWithoutARoom() {
        #expect(!OpenThreadMark.isMarked(rowEventId: "$root", rowRoomId: nil, rowTimelineIsThread: false, panel: Self.panel))
    }
}
