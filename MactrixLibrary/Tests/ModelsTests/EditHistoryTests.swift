import Foundation
import Models
import Testing

/// MATRIX-209: the edit history's version list and its place in the action
/// model.
struct EditHistoryTests {
    private typealias Version = EditHistoryVersion<String>

    /// The SDK's order: the original, then each edit in the order applied.
    private static let revisions: [(body: Version.Body, timestamp: UInt64?)] = [
        (body: .message("First draft"), timestamp: 1_000),
        (body: .unableToDecrypt(.withheldBySender), timestamp: 2_500),
        (body: .message("Final text"), timestamp: 4_000),
    ]

    // MARK: - Version list

    @Test func versionsAreNewestFirst() {
        let versions = Version.newestFirst(Self.revisions)
        #expect(versions.map(\.id) == [2, 1, 0])
        #expect(versions.map(\.body) == [.message("Final text"), .unableToDecrypt(.withheldBySender), .message("First draft")])
    }

    @Test func onlyTheOldestVersionIsTheOriginal() {
        let versions = Version.newestFirst(Self.revisions)
        #expect(versions.map(\.isOriginal) == [false, false, true])
        #expect(versions.last?.body == .message("First draft"))
    }

    @Test func undecryptableVersionKeepsItsPlaceAndTime() {
        let versions = Version.newestFirst(Self.revisions)
        #expect(versions[1].body == .unableToDecrypt(.withheldBySender))
        #expect(versions[1].date == Date(timeIntervalSince1970: 2.5))
        #expect(!versions[1].isOriginal)
    }

    @Test func timestampsAreMilliseconds() {
        let versions = Version.newestFirst(Self.revisions)
        #expect(versions.map(\.date) == [Date(timeIntervalSince1970: 4), Date(timeIntervalSince1970: 2.5), Date(timeIntervalSince1970: 1)])
    }

    @Test func versionWithoutATimestampHasNoDate() {
        let versions = Version.newestFirst([(body: .message("Only"), timestamp: nil)])
        #expect(versions.count == 1)
        #expect(versions[0].date == nil)
        #expect(versions[0].isOriginal)
    }

    @Test func noRevisionsGiveAnEmptyList() {
        #expect(Version.newestFirst([]).isEmpty)
    }

    // MARK: - Action model

    private func subject(
        _ content: MessageActionSubject.Content = .text,
        eventId: String? = "$event",
        isEdited: Bool = true,
        isInMergedChat: Bool = false
    ) -> MessageActionSubject {
        MessageActionSubject(
            content: content,
            isOwn: false,
            eventId: eventId,
            canBeRepliedTo: eventId != nil,
            isPinned: false,
            copyableText: "hello",
            isForwardable: true,
            isInMergedChat: isInMergedChat,
            isEdited: isEdited
        )
    }

    private func item(_ subject: MessageActionSubject, on surface: MessageActionSurface) -> MessageActionItem? {
        MessageActionModel.items(for: subject, on: surface).first { $0.action == .showEditHistory }
    }

    @Test func editedMessageOffersShowEditHistoryAfterForward() {
        let actions = MessageActionModel.items(for: subject(), on: .contextMenu).map(\.action)
        let forward = actions.firstIndex(of: .forward)
        #expect(forward.map { actions[$0 + 1] } == .showEditHistory)
        #expect(item(subject(), on: .contextMenu) == MessageActionItem(action: .showEditHistory, section: .modify, isEnabled: true))
    }

    @Test func messageThatWasNotEditedHasNoEditHistory() {
        #expect(item(subject(isEdited: false), on: .contextMenu) == nil)
    }

    @Test func redactedMessageHasNoEditHistory() {
        #expect(item(subject(.redacted), on: .contextMenu) == nil)
    }

    @Test func localEchoShowsEditHistoryDisabled() {
        #expect(item(subject(eventId: nil), on: .contextMenu)?.isEnabled == false)
    }

    @Test func onlyTheContextMenuOffersEditHistory() {
        #expect(item(subject(), on: .hoverRow) == nil)
        #expect(item(subject(), on: .editMenu) == nil)
    }

    @Test func mergedChatOffersEditHistory() {
        #expect(item(subject(isInMergedChat: true), on: .contextMenu)?.isEnabled == true)
        let route = MergedChatRouting.route(for: .showEditHistory, eventRoomId: "!a", rooms: ["!a", "!b"])
        #expect(route == .room("!a"))
    }
}
