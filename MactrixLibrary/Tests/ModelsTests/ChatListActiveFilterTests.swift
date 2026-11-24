import Models
import Testing

/// MATRIX-226: the sidebar header shows a chip for every filter but the
/// plain Inbox, named as the list's section title is.
struct ChatListActiveFilterTests {
    private let labels = ChatLabelDocument(labels: [
        ChatLabel(id: "work", name: "Work", colorIndex: 6, icon: "briefcase", rooms: ["!a"]),
        ChatLabel(id: "plain", name: "Plain", rooms: ["!b"]),
    ])

    private let spaceNames = ["!dev": "DevObsessed"]

    private func chip(_ rail: ChatListRailFilter, _ list: ChatListFilter = .inbox) -> ChatListActiveFilter? {
        ChatListActiveFilter.chip(
            rail: rail,
            list: list,
            labels: labels,
            spaceName: { spaceNames[$0] },
            paletteCount: 12
        )
    }

    @Test
    func plainInboxHasNoChip() {
        #expect(chip(.inbox) == nil)
    }

    @Test
    func listFilterAloneIsAnAccentChip() {
        #expect(chip(.inbox, .unread) == ChatListActiveFilter(title: "Unread", systemImage: "circlebadge", tint: .accent))
        #expect(chip(.inbox, .snoozed)?.title == "Snoozed")
    }

    @Test
    func labelChipHasTheLabelsNameIconAndColor() {
        #expect(chip(.label("work")) == ChatListActiveFilter(title: "Work", systemImage: "briefcase", tint: .palette(6)))
    }

    @Test
    func labelWithNoIconOrColorUsesTheTagAndTheNeutralFill() {
        #expect(chip(.label("plain")) == ChatListActiveFilter(title: "Plain", systemImage: "tag", tint: .palette(nil)))
    }

    /// Both filters: the rail item's name and color, then the list filter.
    @Test
    func labelAndListFilterJoinTheirNames() {
        #expect(chip(.label("work"), .unread) == ChatListActiveFilter(title: "Work · Unread", systemImage: "briefcase", tint: .palette(6)))
    }

    /// A space's color is the color of its initials square on the rail.
    @Test
    func spaceChipHasTheSpaceGlyphAndItsRailColor() {
        let index = ChatListRailSpace(id: "!dev", name: "DevObsessed").colorIndex(paletteCount: 12)
        #expect(chip(.space("!dev")) == ChatListActiveFilter(title: "DevObsessed", systemImage: "square.grid.2x2", tint: .palette(index)))
        #expect(chip(.space("!dev"), .people)?.title == "DevObsessed · People")
    }

    /// A label or a space that is not known counts as the Inbox, as the chat
    /// list does.
    @Test
    func unknownRailItemCountsAsTheInbox() {
        #expect(chip(.label("gone")) == nil)
        #expect(chip(.space("!gone")) == nil)
        #expect(chip(.space("!gone"), .unread)?.title == "Unread")
    }
}
