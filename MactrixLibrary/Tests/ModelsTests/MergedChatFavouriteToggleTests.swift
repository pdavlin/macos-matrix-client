import Foundation
@testable import Models
import Testing

/// MATRIX-189: Favorite and Unfavorite on a merged row change every member.
struct MergedChatFavouriteToggleTests {
    /// "!s3" is a member the window's filter hides: the chat list has no
    /// entry for it.
    private let seth = MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2", "!s3"])

    private func entry(_ id: String, isFavourite: Bool = false) -> ChatListEntry {
        ChatListEntry(
            row: ChatListRowModel(id: id, title: "Title \(id)", isDirect: true),
            isFavourite: isFavourite
        )
    }

    private func merged(favourites: Set<String> = []) throws -> MergedChatListEntry {
        let entries = ["!s1", "!s2", "!other"].map { entry($0, isFavourite: favourites.contains($0)) }
        let items = ChatListMerging.items(entries: entries, document: MergedChatDocument(merges: [seth]))
        return try #require(items.first { $0.id == seth.id }?.mergedChat)
    }

    @Test
    func favoriteSetsTheTagOnEveryMemberAlsoTheHiddenOne() throws {
        let merged = try merged()
        #expect(merged.memberRoomIds == ["!s1", "!s2"])

        let toggle = MergedChatFavouriteToggle(merged: merged)

        #expect(toggle.isFavourite)
        #expect(toggle.roomIds == ["!s1", "!s2", "!s3"])
    }

    @Test
    func unfavoriteClearsTheTagOnEveryMemberWhenOneMemberIsAFavourite() throws {
        let merged = try merged(favourites: ["!s2"])
        #expect(merged.isFavourite)

        let toggle = MergedChatFavouriteToggle(merged: merged)

        #expect(!toggle.isFavourite)
        #expect(toggle.roomIds == ["!s1", "!s2", "!s3"])
    }

    @Test
    func unfavoriteWhenEveryMemberIsAFavourite() throws {
        let toggle = try MergedChatFavouriteToggle(merged: merged(favourites: ["!s1", "!s2"]))

        #expect(!toggle.isFavourite)
        #expect(toggle.roomIds == ["!s1", "!s2", "!s3"])
    }

    @Test
    func labelsMatchTheRoomMenu() throws {
        let favorite = try MergedChatFavouriteToggle(merged: merged())
        #expect(favorite.title == "Favorite")
        #expect(favorite.systemImage == "heart")

        let unfavorite = try MergedChatFavouriteToggle(merged: merged(favourites: ["!s1"]))
        #expect(unfavorite.title == "Unfavorite")
        #expect(unfavorite.systemImage == "heart.slash")
    }
}
