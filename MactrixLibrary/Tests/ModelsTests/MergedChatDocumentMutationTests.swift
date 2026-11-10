import Foundation
@testable import Models
import Testing

/// MATRIX-140: the merged-chats mutations and their invariants.
struct MergedChatDocumentMutationTests {
    /// Seth over !a and !b (default !a, avatar !b), Ana over !c, !d, !e.
    private static func sample() -> MergedChatDocument {
        MergedChatDocument(merges: [
            MergedChat(id: "seth", name: "Seth", rooms: ["!a", "!b"], defaultRoom: "!a", avatarRoom: "!b"),
            MergedChat(id: "ana", name: "Ana", rooms: ["!c", "!d", "!e"]),
        ])
    }

    // MARK: create

    @Test
    func createAppendsAndReturnsTheId() throws {
        var document = MergedChatDocument()
        let id = document.create(name: "Seth", rooms: ["!a", "!b", "!a"], defaultRoom: "!b", avatarRoom: "!a", id: "seth")
        #expect(id == "seth")
        let merge = try #require(document.merge(id: "seth"))
        #expect(merge == MergedChat(id: "seth", name: "Seth", rooms: ["!a", "!b"], defaultRoom: "!b", avatarRoom: "!a"))
    }

    @Test
    func createGeneratesAnIdByDefault() throws {
        var document = MergedChatDocument()
        let created = document.create(name: "M", rooms: ["!a", "!b"])
        let id = try #require(created)
        #expect(UUID(uuidString: id) != nil)
        #expect(document.merge(id: id) != nil)
    }

    @Test
    func createRefusesFewerThanTwoDistinctRooms() {
        var document = MergedChatDocument()
        #expect(document.create(name: "M", rooms: []) == nil)
        #expect(document.create(name: "M", rooms: ["!a"]) == nil)
        #expect(document.create(name: "M", rooms: ["!a", "!a"]) == nil)
        #expect(document.merges.isEmpty)
    }

    @Test
    func createRefusesATakenId() {
        var document = Self.sample()
        #expect(document.create(name: "Other", rooms: ["!x", "!y"], id: "seth") == nil)
        #expect(document == Self.sample())
    }

    @Test
    func createRefusesNonMemberDefaultOrAvatarRoom() {
        var document = MergedChatDocument()
        #expect(document.create(name: "M", rooms: ["!a", "!b"], defaultRoom: "!z") == nil)
        #expect(document.create(name: "M", rooms: ["!a", "!b"], avatarRoom: "!z") == nil)
        #expect(document.merges.isEmpty)
    }

    @Test
    func createMovesRoomsOutOfOtherMerges() {
        var document = Self.sample()
        #expect(document.create(name: "New", rooms: ["!c", "!x"], id: "new") == "new")
        #expect(document.merge(id: "ana")?.rooms == ["!d", "!e"])
        #expect(document.merge(containing: "!c")?.id == "new")
    }

    @Test
    func createRemovesAMergeLeftWithOneRoom() {
        var document = Self.sample()
        // Seth loses !b, so it has one room and goes.
        document.create(name: "New", rooms: ["!b", "!x"], id: "new")
        #expect(document.merge(id: "seth") == nil)
        #expect(document.merges.map(\.id) == ["ana", "new"])
    }

    // MARK: rename

    @Test
    func renameChangesOnlyTheName() {
        var document = Self.sample()
        #expect(document.rename("seth", to: "Seth K") == true)
        #expect(document.merge(id: "seth")?.name == "Seth K")
        #expect(document.merge(id: "seth")?.rooms == ["!a", "!b"])
        #expect(document.rename("missing", to: "X") == false)
    }

    // MARK: setRooms

    @Test
    func setRoomsReplacesTheMembers() {
        var document = Self.sample()
        #expect(document.setRooms(["!b", "!x", "!b"], for: "seth") == true)
        let seth = document.merge(id: "seth")
        #expect(seth?.rooms == ["!b", "!x"])
        // !a left, so the default room clears; !b stayed, so the avatar
        // room stays.
        #expect(seth?.defaultRoom == nil)
        #expect(seth?.avatarRoom == "!b")
    }

    @Test
    func setRoomsMovesRoomsAndRemovesEmptiedMerges() {
        var document = Self.sample()
        #expect(document.setRooms(["!a", "!b", "!c", "!d"], for: "seth") == true)
        // Ana keeps only !e and goes.
        #expect(document.merges.map(\.id) == ["seth"])
    }

    @Test
    func setRoomsRefusesFewerThanTwoRoomsAndUnknownIds() {
        var document = Self.sample()
        #expect(document.setRooms(["!a"], for: "seth") == false)
        #expect(document.setRooms(["!a", "!a"], for: "seth") == false)
        #expect(document.setRooms(["!x", "!y"], for: "missing") == false)
        #expect(document == Self.sample())
    }

    // MARK: addRoom

    @Test
    func addRoomAppends() {
        var document = Self.sample()
        #expect(document.addRoom("!x", to: "seth") == true)
        #expect(document.merge(id: "seth")?.rooms == ["!a", "!b", "!x"])
    }

    @Test
    func addRoomThatIsAlreadyAMemberIsANoOp() {
        var document = Self.sample()
        #expect(document.addRoom("!a", to: "seth") == true)
        #expect(document == Self.sample())
    }

    @Test
    func addRoomMovesItFromAnotherMerge() {
        var document = Self.sample()
        #expect(document.addRoom("!c", to: "seth") == true)
        #expect(document.merge(id: "seth")?.rooms == ["!a", "!b", "!c"])
        #expect(document.merge(id: "ana")?.rooms == ["!d", "!e"])
    }

    @Test
    func addRoomRemovesAMergeLeftWithOneRoom() {
        var document = Self.sample()
        #expect(document.addRoom("!a", to: "ana") == true)
        #expect(document.merge(id: "seth") == nil)
        #expect(document.merge(id: "ana")?.rooms == ["!c", "!d", "!e", "!a"])
    }

    @Test
    func addRoomRefusesAnUnknownMerge() {
        var document = Self.sample()
        #expect(document.addRoom("!c", to: "missing") == false)
        #expect(document == Self.sample())
    }

    // MARK: removeRoom

    @Test
    func removeRoomKeepsAMergeWithTwoOrMoreRooms() {
        var document = Self.sample()
        #expect(document.removeRoom("!d", from: "ana") == true)
        #expect(document.merge(id: "ana")?.rooms == ["!c", "!e"])
    }

    @Test
    func removeRoomDownToOneRoomRemovesTheMerge() {
        var document = Self.sample()
        #expect(document.removeRoom("!a", from: "seth") == true)
        #expect(document.merge(id: "seth") == nil)
        #expect(document.merge(containing: "!b") == nil)
    }

    @Test
    func removeRoomClearsDefaultAndAvatarRoom() {
        var document = MergedChatDocument(merges: [
            MergedChat(id: "m", name: "M", rooms: ["!a", "!b", "!c"], defaultRoom: "!a", avatarRoom: "!a"),
        ])
        #expect(document.removeRoom("!a", from: "m") == true)
        #expect(document.merge(id: "m")?.defaultRoom == nil)
        #expect(document.merge(id: "m")?.avatarRoom == nil)
    }

    @Test
    func removeRoomRefusesANonMemberOrUnknownMerge() {
        var document = Self.sample()
        #expect(document.removeRoom("!c", from: "seth") == false)
        #expect(document.removeRoom("!a", from: "missing") == false)
        #expect(document == Self.sample())
    }

    // MARK: setDefaultRoom, setAvatarRoom

    @Test
    func setDefaultRoomAcceptsAMemberOrNil() {
        var document = Self.sample()
        #expect(document.setDefaultRoom("!b", for: "seth") == true)
        #expect(document.merge(id: "seth")?.defaultRoom == "!b")
        #expect(document.setDefaultRoom(nil, for: "seth") == true)
        #expect(document.merge(id: "seth")?.defaultRoom == nil)
    }

    @Test
    func setDefaultRoomRefusesANonMember() {
        var document = Self.sample()
        #expect(document.setDefaultRoom("!c", for: "seth") == false)
        #expect(document.setDefaultRoom("!a", for: "missing") == false)
        #expect(document == Self.sample())
    }

    @Test
    func setAvatarRoomAcceptsAMemberOrNil() {
        var document = Self.sample()
        #expect(document.setAvatarRoom("!a", for: "seth") == true)
        #expect(document.merge(id: "seth")?.avatarRoom == "!a")
        #expect(document.setAvatarRoom(nil, for: "seth") == true)
        #expect(document.merge(id: "seth")?.avatarRoom == nil)
    }

    @Test
    func setAvatarRoomRefusesANonMember() {
        var document = Self.sample()
        #expect(document.setAvatarRoom("!c", for: "seth") == false)
        #expect(document.setAvatarRoom("!a", for: "missing") == false)
        #expect(document == Self.sample())
    }

    // MARK: unmerge

    @Test
    func unmergeRemovesTheMerge() {
        var document = Self.sample()
        #expect(document.unmerge("seth") == true)
        #expect(document.merges.map(\.id) == ["ana"])
        #expect(document.unmerge("seth") == false)
    }

    // MARK: pruneRooms

    @Test
    func pruneRoomsDropsRoomsTheAccountLeft() {
        var document = Self.sample()
        #expect(document.pruneRooms(keeping: ["!a", "!b", "!c", "!e"]) == true)
        #expect(document.merge(id: "seth") == Self.sample().merge(id: "seth"))
        #expect(document.merge(id: "ana")?.rooms == ["!c", "!e"])
    }

    @Test
    func pruneRoomsRemovesMergesLeftWithOneRoomAndClearsRoles() {
        var document = MergedChatDocument(merges: [
            MergedChat(id: "seth", name: "Seth", rooms: ["!a", "!b"]),
            MergedChat(id: "m", name: "M", rooms: ["!c", "!d", "!e"], defaultRoom: "!c", avatarRoom: "!d"),
        ])
        #expect(document.pruneRooms(keeping: ["!a", "!d", "!e"]) == true)
        #expect(document.merge(id: "seth") == nil)
        let merge = document.merge(id: "m")
        #expect(merge?.rooms == ["!d", "!e"])
        #expect(merge?.defaultRoom == nil)
        #expect(merge?.avatarRoom == "!d")
    }

    @Test
    func pruneRoomsReportsNoChange() {
        var document = Self.sample()
        #expect(document.pruneRooms(keeping: ["!a", "!b", "!c", "!d", "!e", "!z"]) == false)
        #expect(document == Self.sample())
    }

    // MARK: normalize

    @Test
    func normalizeRestoresTheInvariants() {
        var document = MergedChatDocument(merges: [
            MergedChat(id: "x", name: "X", rooms: ["!a", "!b", "!a"], defaultRoom: "!z", avatarRoom: "!b"),
            MergedChat(id: "y", name: "Y", rooms: ["!b", "!c", "!d"]),
            MergedChat(id: "z", name: "Z", rooms: ["!c", "!e"]),
            MergedChat(id: "w", name: "W", rooms: ["!f"]),
        ])
        document.normalize()
        #expect(document.merges == [
            MergedChat(id: "x", name: "X", rooms: ["!a", "!b"], avatarRoom: "!b"),
            MergedChat(id: "y", name: "Y", rooms: ["!c", "!d"]),
        ])
    }

    @Test
    func normalizeLeavesAValidDocumentAlone() {
        var document = Self.sample()
        document.normalize()
        #expect(document == Self.sample())
    }
}
