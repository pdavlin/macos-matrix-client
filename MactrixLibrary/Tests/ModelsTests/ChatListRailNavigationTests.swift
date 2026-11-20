import Foundation
@testable import Models
import Testing

/// MATRIX-217: the rail order, the ⌘1…⌘9 keys, and the ⇧⌘] / ⇧⌘[ walk.
struct ChatListRailNavigationTests {
    private static let spaces = [
        ChatListRailSpace(id: "!dev", name: "DevObsessed", badge: .dot),
        ChatListRailSpace(id: "!home", name: "Home"),
    ]

    private static let labels = [
        ChatLabel(id: "work", name: "Work"),
        ChatLabel(id: "fam", name: "Family"),
    ]

    private static let items = ChatListRailNavigation.items(spaces: spaces, labels: labels)
    private static let filters = items.map(\.filter)

    // MARK: Rail order

    @Test
    func theInboxThenTheSpacesThenTheLabels() {
        #expect(Self.items == [
            ChatListRailItem(filter: .inbox, name: "Inbox"),
            ChatListRailItem(filter: .space("!dev"), name: "DevObsessed"),
            ChatListRailItem(filter: .space("!home"), name: "Home"),
            ChatListRailItem(filter: .label("work"), name: "Work"),
            ChatListRailItem(filter: .label("fam"), name: "Family"),
        ])
    }

    @Test
    func noSpacesAndNoLabelsLeavesTheInbox() {
        #expect(ChatListRailNavigation.items(spaces: [], labels: []) == [ChatListRailItem(filter: .inbox, name: "Inbox")])
    }

    // MARK: ⌘1…⌘9

    @Test
    func keysFollowTheRailOrder() {
        let targets = ChatListRailNavigation.shortcutTargets(in: Self.items).map(\.filter)
        #expect(targets == [.inbox, .space("!dev"), .space("!home"), .label("work"), .label("fam")])
    }

    @Test
    func onlyNineItemsGetAKey() {
        let labels = (0 ..< 12).map { ChatLabel(id: "l\($0)", name: "L\($0)") }
        let items = ChatListRailNavigation.items(spaces: Self.spaces, labels: labels)
        let targets = ChatListRailNavigation.shortcutTargets(in: items).map(\.filter)
        #expect(targets.count == 9)
        #expect(targets.first == .inbox)
        #expect(targets.last == .label("l5"))
    }

    // MARK: ⇧⌘] and ⇧⌘[

    @Test
    func nextStepsDownAndWrapsToTheInbox() {
        #expect(ChatListRailNavigation.next(after: .inbox, in: Self.filters) == .space("!dev"))
        #expect(ChatListRailNavigation.next(after: .space("!home"), in: Self.filters) == .label("work"))
        #expect(ChatListRailNavigation.next(after: .label("fam"), in: Self.filters) == .inbox)
    }

    @Test
    func previousStepsUpAndWrapsToTheLastItem() {
        #expect(ChatListRailNavigation.previous(before: .label("work"), in: Self.filters) == .space("!home"))
        #expect(ChatListRailNavigation.previous(before: .space("!dev"), in: Self.filters) == .inbox)
        #expect(ChatListRailNavigation.previous(before: .inbox, in: Self.filters) == .label("fam"))
    }

    @Test
    func anItemNotOnTheRailStepsToAnEnd() {
        #expect(ChatListRailNavigation.next(after: .label("gone"), in: Self.filters) == .inbox)
        #expect(ChatListRailNavigation.previous(before: .label("gone"), in: Self.filters) == .label("fam"))
    }

    @Test
    func theInboxAloneHasNoOtherItem() {
        #expect(ChatListRailNavigation.next(after: .inbox, in: [.inbox]) == nil)
        #expect(ChatListRailNavigation.previous(before: .inbox, in: [.inbox]) == nil)
        #expect(ChatListRailNavigation.next(after: .inbox, in: []) == nil)
        #expect(ChatListRailNavigation.previous(before: .inbox, in: []) == nil)
    }
}
