import Foundation
@testable import Models
import Testing

/// MATRIX-141: merged chats folded into the chat list.
struct ChatListMergingTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(
        _ id: String,
        minutesAgo: Double? = nil,
        title: String? = nil,
        unread: ChatListUnread = ChatListUnread(),
        network: ChatListNetwork? = nil,
        avatarUrl: String? = nil,
        isFavourite: Bool = false,
        hasSendFailure: Bool = false
    ) -> ChatListEntry {
        ChatListEntry(
            row: ChatListRowModel(
                id: id,
                title: title ?? "Title \(id)",
                avatarUrl: avatarUrl,
                isDirect: true,
                preview: "Preview \(id)",
                timestamp: "Time \(id)",
                unread: unread,
                hasSendFailure: hasSendFailure,
                network: network
            ),
            lastActivity: minutesAgo.map { Self.base.addingTimeInterval(-$0 * 60) },
            isFavourite: isFavourite
        )
    }

    private func document(_ merges: MergedChat...) -> MergedChatDocument {
        MergedChatDocument(merges: merges)
    }

    private let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"])

    private func mergedEntry(_ items: [ChatListItem], _ id: String = "m-seth") -> MergedChatListEntry? {
        items.first { $0.id == id }?.mergedChat
    }

    // MARK: Order

    @Test
    func emptyDocumentPassesRoomsThrough() {
        let entries = [entry("!a", minutesAgo: 1), entry("!b", minutesAgo: 2)]
        let items = ChatListMerging.items(entries: entries, document: MergedChatDocument())
        #expect(items == entries.map(ChatListItem.room))
    }

    @Test
    func membersLeaveAndTheMergedRowTakesTheNewestMembersPlace() {
        let entries = [
            entry("!a", minutesAgo: 1),
            entry("!s2", minutesAgo: 2),
            entry("!b", minutesAgo: 3),
            entry("!s1", minutesAgo: 4),
            entry("!c", minutesAgo: 5),
        ]
        let items = ChatListMerging.items(entries: entries, document: document(seth))
        #expect(items.map(\.id) == ["!a", "m-seth", "!b", "!c"])
    }

    @Test
    func positionFollowsTheNewestTimeWhenTheSDKOrderDisagrees() {
        // The SDK put !s1 first, but !s2 has the newer event.
        let entries = [
            entry("!s1", minutesAgo: 9),
            entry("!a", minutesAgo: 5),
            entry("!s2", minutesAgo: 1),
        ]
        let items = ChatListMerging.items(entries: entries, document: document(seth))
        #expect(items.map(\.id) == ["!a", "m-seth"])
        #expect(mergedEntry(items)?.newestRoomId == "!s2")
    }

    @Test
    func aMissingTimeIsTheOldestAndATieGoesToTheSDKOrder() {
        let missing = ChatListMerging.items(
            entries: [entry("!s1"), entry("!s2", minutesAgo: 30)],
            document: document(seth)
        )
        #expect(mergedEntry(missing)?.newestRoomId == "!s2")

        let tie = ChatListMerging.items(
            entries: [entry("!s2", minutesAgo: 3), entry("!s1", minutesAgo: 3)],
            document: document(seth)
        )
        #expect(mergedEntry(tie)?.newestRoomId == "!s2")

        let bothMissing = ChatListMerging.items(entries: [entry("!s1"), entry("!s2")], document: document(seth))
        #expect(mergedEntry(bothMissing)?.newestRoomId == "!s1")
    }

    // MARK: Row values

    @Test
    func rowUsesTheNameAndTheNewestMembersPreviewTimestampAndTime() throws {
        let items = ChatListMerging.items(
            entries: [entry("!s1", minutesAgo: 10), entry("!s2", minutesAgo: 2)],
            document: document(seth)
        )
        let merged = try #require(mergedEntry(items))
        #expect(merged.row.id == "m-seth")
        #expect(merged.row.title == "Seth")
        #expect(merged.row.preview == "Preview !s2")
        #expect(merged.row.timestamp == "Time !s2")
        #expect(merged.lastActivity == Self.base.addingTimeInterval(-120))
        #expect(merged.memberRoomIds == ["!s1", "!s2"])
        #expect(items.first?.roomIds == ["!s1", "!s2"])
    }

    @Test
    func aBlankNameFallsBackToTheAvatarMembersTitle() {
        let blank = MergedChat(id: "m-seth", name: "  ", rooms: ["!s1", "!s2"])
        let items = ChatListMerging.items(
            entries: [entry("!s1", minutesAgo: 1, title: "Seth R"), entry("!s2", minutesAgo: 2)],
            document: document(blank)
        )
        #expect(mergedEntry(items)?.row.title == "Seth R")
    }

    @Test
    func nameIsTrimmed() {
        let padded = MergedChat(id: "m-seth", name: " Seth \n", rooms: ["!s1", "!s2"])
        let items = ChatListMerging.items(entries: [entry("!s1"), entry("!s2")], document: document(padded))
        #expect(mergedEntry(items)?.row.title == "Seth")
    }

    @Test
    func aSendFailureOnAnyMemberShows() {
        let items = ChatListMerging.items(
            entries: [entry("!s1", minutesAgo: 1), entry("!s2", minutesAgo: 9, hasSendFailure: true)],
            document: document(seth)
        )
        #expect(mergedEntry(items)?.row.hasSendFailure == true)
    }

    // MARK: Unread and mute

    @Test
    func unreadCountsAddUpAndAnyMentionOrFlagCounts() throws {
        let items = ChatListMerging.items(
            entries: [
                entry("!s1", minutesAgo: 1, unread: ChatListUnread(count: 3, isUnread: true)),
                entry("!s2", minutesAgo: 2, unread: ChatListUnread(count: 4, hasMention: true, isUnread: true)),
            ],
            document: document(seth)
        )
        let unread = try #require(mergedEntry(items)?.row.unread)
        #expect(unread == ChatListUnread(count: 7, hasMention: true, isUnread: true))
    }

    @Test
    func aMarkedUnreadMemberMakesTheRowUnreadWithoutACount() {
        let unread = ChatListMerging.unread(of: [ChatListUnread(), ChatListUnread(isUnread: true)])
        #expect(unread == ChatListUnread(count: 0, isUnread: true))
    }

    @Test
    func countsSaturate() {
        let unread = ChatListMerging.unread(of: [
            ChatListUnread(count: UInt64.max - 1, isUnread: true),
            ChatListUnread(count: 5, isUnread: true),
        ])
        #expect(unread.count == UInt64.max)
    }

    @Test
    func mutedOnlyWhenEveryMemberIsMuted() {
        let some = ChatListMerging.unread(of: [ChatListUnread(isMuted: true), ChatListUnread()])
        #expect(!some.isMuted)

        let every = ChatListMerging.unread(of: [ChatListUnread(isMuted: true), ChatListUnread(isMuted: true)])
        #expect(every.isMuted)
        #expect(!every.isMutedByLabel)
    }

    @Test
    func mutedByLabelOnlyWhenEveryMemberIsMutedByALabel() {
        let mixed = ChatListMerging.unread(of: [ChatListUnread(isMuted: true), ChatListUnread(isMutedByLabel: true)])
        #expect(mixed.isMuted)
        #expect(!mixed.isMutedByLabel)

        let labels = ChatListMerging.unread(of: [ChatListUnread(isMutedByLabel: true), ChatListUnread(isMutedByLabel: true)])
        #expect(labels.isMuted)
        #expect(labels.isMutedByLabel)
    }

    @Test
    func aMutedMemberAddsNoCountAndNoMention() {
        let unread = ChatListMerging.unread(of: [
            ChatListUnread(count: 3, isUnread: true),
            ChatListUnread(count: 4, hasMention: true, isUnread: true, isMuted: true),
        ])
        #expect(unread == ChatListUnread(count: 3, isUnread: true))
    }

    @Test
    func aLabelMutedMemberAddsNoCount() {
        let unread = ChatListMerging.unread(of: [
            ChatListUnread(count: 2, isUnread: true),
            ChatListUnread(count: 6, hasMention: true, isUnread: true, isMutedByLabel: true),
        ])
        #expect(unread == ChatListUnread(count: 2, isUnread: true))
    }

    @Test
    func onlyAMutedMemberUnreadLeavesTheRowRead() {
        let unread = ChatListMerging.unread(of: [
            ChatListUnread(),
            ChatListUnread(count: 5, isUnread: true, isMuted: true),
        ])
        #expect(unread == ChatListUnread())
    }

    @Test
    func everyMemberMutedShowsTheMutedSum() {
        let unread = ChatListMerging.unread(of: [
            ChatListUnread(count: 1, isUnread: true, isMuted: true),
            ChatListUnread(count: 4, hasMention: true, isUnread: true, isMutedByLabel: true),
        ])
        #expect(unread == ChatListUnread(count: 5, hasMention: true, isUnread: true, isMuted: true))
    }

    @Test
    func markedUnreadOnAMutedMemberStillMakesTheRowUnread() {
        let flagged = ChatListMerging.unread(
            of: [ChatListUnread(), ChatListUnread(count: 2, isUnread: true, isMuted: true)],
            anyMarkedUnread: true
        )
        #expect(flagged == ChatListUnread(count: 0, isUnread: true))

        // Unread with a zero count can only be the marked-unread flag.
        let derived = ChatListMerging.unread(of: [ChatListUnread(), ChatListUnread(isUnread: true, isMuted: true)])
        #expect(derived == ChatListUnread(count: 0, isUnread: true))
    }

    @Test
    func theEntryMarkedUnreadFlagReachesTheRow() {
        var muted = entry("!s2", minutesAgo: 2, unread: ChatListUnread(count: 3, isUnread: true, isMuted: true))
        muted.isMarkedUnread = true
        let items = ChatListMerging.items(entries: [entry("!s1", minutesAgo: 1), muted], document: document(seth))
        #expect(mergedEntry(items)?.row.unread == ChatListUnread(count: 0, isUnread: true))
    }

    @Test
    func noMembersIsTheReadUnmutedState() {
        #expect(ChatListMerging.unread(of: []) == ChatListUnread())
    }

    // MARK: Networks

    @Test
    func networksAreDistinctInMergeOrder() throws {
        let merge = MergedChat(id: "m", name: "Seth", rooms: ["!s1", "!s2", "!s3", "!s4"])
        let items = ChatListMerging.items(
            entries: [
                entry("!s4", minutesAgo: 1, network: .googleChat),
                entry("!s3", minutesAgo: 2),
                entry("!s2", minutesAgo: 3, network: .slack),
                entry("!s1", minutesAgo: 4, network: .slack),
            ],
            document: document(merge)
        )
        let merged = try #require(mergedEntry(items, "m"))
        #expect(merged.networks == [.slack, .googleChat])
        #expect(merged.row.network == .slack)
        #expect(merged.row.additionalNetworks == [.googleChat])
        #expect(merged.row.badgeNetworks == [.slack, .googleChat])
    }

    @Test
    func badgeNetworksDropRepeatsAndStopAtTheLimit() {
        var row = ChatListRowModel(id: "m", title: "Seth", network: .slack)
        row.additionalNetworks = [.slack, .whatsApp, .signal, .telegram]
        #expect(row.badgeNetworks == [.slack, .whatsApp, .signal])
        #expect(ChatListRowModel(id: "!a", title: "A").badgeNetworks.isEmpty)
        #expect(ChatListRowModel(id: "!a", title: "A", network: .discord).badgeNetworks == [.discord])
    }

    @Test
    func accessibilityLabelNamesEveryBadgeNetwork() {
        var row = ChatListRowModel(id: "m", title: "Seth", network: .slack)
        row.additionalNetworks = [.googleChat]
        #expect(row.accessibilityLabel == "Seth, Slack, Google Chat")
    }
}

/// MATRIX-141: the avatar, absent members, favourites, and malformed
/// documents.
extension ChatListMergingTests {
    // MARK: Avatar

    @Test
    func theChosenAvatarRoomWins() {
        let merge = MergedChat(id: "m", name: "Seth", rooms: ["!s1", "!s2"], avatarRoom: "!s2")
        let items = ChatListMerging.items(
            entries: [entry("!s1", avatarUrl: "mxc://a/1"), entry("!s2")],
            document: document(merge)
        )
        let merged = mergedEntry(items, "m")
        #expect(merged?.avatarRoomId == "!s2")
        #expect(merged?.row.avatarUrl == nil)
    }

    @Test
    func withoutAChoiceTheFirstMemberWithAnImageWins() {
        let merge = MergedChat(id: "m", name: "Seth", rooms: ["!s1", "!s2", "!s3"])
        let items = ChatListMerging.items(
            entries: [entry("!s3", avatarUrl: "mxc://a/3"), entry("!s1"), entry("!s2", avatarUrl: "mxc://a/2")],
            document: document(merge)
        )
        let merged = mergedEntry(items, "m")
        #expect(merged?.avatarRoomId == "!s2")
        #expect(merged?.row.avatarUrl == "mxc://a/2")
    }

    @Test
    func aDirectChatHeroAvatarCountsAsAnImage() {
        let merge = MergedChat(id: "m", name: "Seth", rooms: ["!s1", "!s2"])
        var withHero = entry("!s2")
        withHero.row.heroes = [ChatListHero(userId: "@slack_u1:x", displayName: "Seth", avatarUrl: "mxc://a/h")]
        let items = ChatListMerging.items(entries: [entry("!s1"), withHero], document: document(merge))
        let merged = mergedEntry(items, "m")
        #expect(merged?.avatarRoomId == "!s2")
        #expect(merged?.row.heroes == withHero.row.heroes)
    }

    @Test
    func withoutAnyImageTheFirstMemberInMergeOrderWins() {
        let items = ChatListMerging.items(
            entries: [entry("!s2", minutesAgo: 1), entry("!s1", minutesAgo: 2)],
            document: document(seth)
        )
        #expect(mergedEntry(items)?.avatarRoomId == "!s1")
    }

    @Test
    func anAbsentAvatarRoomFallsBackToTheRule() {
        let merge = MergedChat(id: "m", name: "Seth", rooms: ["!s1", "!s2", "!gone"], avatarRoom: "!gone")
        let items = ChatListMerging.items(
            entries: [entry("!s1"), entry("!s2", avatarUrl: "mxc://a/2")],
            document: document(merge)
        )
        #expect(mergedEntry(items, "m")?.avatarRoomId == "!s2")
    }

    // MARK: Absent members

    @Test
    func aMergeWithOnePresentMemberShowsAndAggregatesOnlyIt() throws {
        let items = ChatListMerging.items(
            entries: [entry("!a", minutesAgo: 1), entry("!s2", minutesAgo: 2, unread: ChatListUnread(count: 2, isUnread: true))],
            document: document(seth)
        )
        #expect(items.map(\.id) == ["!a", "m-seth"])
        let merged = try #require(mergedEntry(items))
        #expect(merged.memberRoomIds == ["!s2"])
        #expect(merged.row.unread.count == 2)
        #expect(merged.merge.rooms == ["!s1", "!s2"])
    }

    @Test
    func aMergeWithNoPresentMemberDoesNotShow() {
        let items = ChatListMerging.items(entries: [entry("!a"), entry("!b")], document: document(seth))
        #expect(items.map(\.id) == ["!a", "!b"])
    }

    @Test
    func aMutedAbsentMemberDoesNotMuteTheRow() {
        let items = ChatListMerging.items(entries: [entry("!s1")], document: document(seth))
        #expect(mergedEntry(items)?.row.unread.isMuted == false)
    }

    // MARK: Favourites

    @Test
    func anyFavouriteMemberPinsTheMergedChat() {
        let entries = [
            entry("!fav", minutesAgo: 1, isFavourite: true),
            entry("!s1", minutesAgo: 2),
            entry("!a", minutesAgo: 3),
            entry("!s2", minutesAgo: 4, isFavourite: true),
        ]
        let visible = ChatListMerging.visible(entries: entries, document: document(seth))
        #expect(visible.favorites.map(\.id) == ["!fav", "m-seth"])
        #expect(visible.list.map(\.id) == ["!a"])
        #expect(visible.ordered.map(\.id) == ["!fav", "m-seth", "!a"])
    }

    @Test
    func noFavouriteMemberKeepsTheMergedChatInTheList() {
        let visible = ChatListMerging.visible(
            entries: [entry("!s1", minutesAgo: 1), entry("!s2", minutesAgo: 2)],
            document: document(seth)
        )
        #expect(visible.favorites.isEmpty)
        #expect(visible.list.map(\.id) == ["m-seth"])
    }

    // MARK: Malformed documents

    @Test
    func aRoomInTwoMergesBelongsToTheFirst() {
        let first = MergedChat(id: "m1", name: "One", rooms: ["!x", "!y"])
        let second = MergedChat(id: "m2", name: "Two", rooms: ["!y", "!z"])
        let items = ChatListMerging.items(
            entries: [entry("!y", minutesAgo: 1), entry("!z", minutesAgo: 2), entry("!x", minutesAgo: 3)],
            document: document(first, second)
        )
        #expect(items.map(\.id) == ["m1", "m2"])
        #expect(mergedEntry(items, "m1")?.memberRoomIds == ["!x", "!y"])
        #expect(mergedEntry(items, "m2")?.memberRoomIds == ["!z"])
    }

    @Test
    func aRepeatedEntryCountsOnce() {
        let items = ChatListMerging.items(
            entries: [
                entry("!s1", minutesAgo: 1, unread: ChatListUnread(count: 2, isUnread: true)),
                entry("!s1", minutesAgo: 1, unread: ChatListUnread(count: 2, isUnread: true)),
                entry("!s2", minutesAgo: 2),
            ],
            document: document(seth)
        )
        #expect(items.map(\.id) == ["m-seth"])
        #expect(mergedEntry(items)?.row.unread.count == 2)
    }

    @Test
    func aRepeatedRoomInAMergeIsOneMember() {
        let merge = MergedChat(id: "m", name: "Seth", rooms: ["!s1", "!s1", "!s2"])
        let items = ChatListMerging.items(entries: [entry("!s1"), entry("!s2")], document: document(merge))
        #expect(mergedEntry(items, "m")?.memberRoomIds == ["!s1", "!s2"])
    }

    @Test
    func plainRoomItemsReportTheirOwnValues() {
        let plain = entry("!a", minutesAgo: 1, isFavourite: true)
        let item = ChatListItem.room(plain)
        #expect(item.id == "!a")
        #expect(item.row == plain.row)
        #expect(item.isFavourite)
        #expect(item.lastActivity == plain.lastActivity)
        #expect(item.roomIds == ["!a"])
        #expect(item.mergedChat == nil)
    }
}
