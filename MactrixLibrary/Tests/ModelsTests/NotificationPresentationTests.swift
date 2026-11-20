import Foundation
import Models
import Testing

/// MATRIX-215: whether a notification shows while Mactrix is running.
struct NotificationPresentationTests {
    private let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!slack1", "!slack2"])

    private func shows(
        roomId: String? = "!room",
        isReminder: Bool = false,
        appIsActive: Bool = true,
        keyWindowSelection: ChatSelection?,
        merges: [MergedChat] = []
    ) -> Bool {
        NotificationPresentation.shows(
            roomId: roomId,
            isReminder: isReminder,
            appIsActive: appIsActive,
            keyWindowSelection: keyWindowSelection,
            document: MergedChatDocument(merges: merges)
        )
    }

    // MARK: App active

    /// The message is already on screen.
    @Test func activeWithTheRoomSelectedDoesNotShow() {
        #expect(!shows(keyWindowSelection: .room("!room")))
    }

    @Test func activeWithAnotherRoomSelectedShows() {
        #expect(shows(keyWindowSelection: .room("!other")))
    }

    @Test func activeWithNoChatSelectedShows() {
        #expect(shows(keyWindowSelection: nil))
    }

    /// MATRIX-141: a main window shows a member room as its merged chat.
    @Test func activeWithTheRoomsMergedChatSelectedDoesNotShow() {
        #expect(!shows(roomId: "!slack2", keyWindowSelection: .merged("m-seth"), merges: [seth]))
    }

    @Test func activeWithAnotherMergedChatSelectedShows() {
        let other = MergedChat(id: "m-other", name: "Other", rooms: ["!a", "!b"])
        #expect(shows(roomId: "!slack1", keyWindowSelection: .merged("m-other"), merges: [seth, other]))
    }

    /// A room window (MATRIX-116) of a member room selects the room itself.
    @Test func activeWithAMemberRoomWindowOfTheRoomDoesNotShow() {
        #expect(!shows(roomId: "!slack1", keyWindowSelection: .room("!slack1"), merges: [seth]))
    }

    @Test func activeWithASiblingMemberRoomWindowShows() {
        #expect(shows(roomId: "!slack1", keyWindowSelection: .room("!slack2"), merges: [seth]))
    }

    @Test func activeWithNoRoomIdShows() {
        #expect(shows(roomId: nil, keyWindowSelection: .room("!room")))
    }

    // MARK: App inactive

    @Test func inactiveWithTheRoomSelectedShows() {
        #expect(shows(appIsActive: false, keyWindowSelection: .room("!room")))
    }

    @Test func inactiveWithTheRoomsMergedChatSelectedShows() {
        #expect(shows(roomId: "!slack1", appIsActive: false, keyWindowSelection: .merged("m-seth"), merges: [seth]))
    }

    // MARK: Snooze ends and reminders

    /// MATRIX-207: the user asked for it, so it shows for the open chat too.
    @Test func aReminderForTheSelectedRoomShows() {
        #expect(shows(isReminder: true, keyWindowSelection: .room("!room")))
    }
}
