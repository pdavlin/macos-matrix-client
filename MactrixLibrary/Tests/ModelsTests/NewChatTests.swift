import Models
import Testing

/// MATRIX-75: the pure decisions behind the New Chat screen.
struct MatrixUserIDTests {
    @Test func acceptsPlainUserId() {
        #expect(MatrixUserID.parse("@slackbot:davlin.io") == "@slackbot:davlin.io")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(MatrixUserID.parse("  @alice:example.org\n") == "@alice:example.org")
    }

    @Test func acceptsPortAndIPAddressServerNames() {
        #expect(MatrixUserID.parse("@alice:example.org:8448") == "@alice:example.org:8448")
        #expect(MatrixUserID.parse("@alice:[::1]:8448") == "@alice:[::1]:8448")
        #expect(MatrixUserID.parse("@alice:127.0.0.1") == "@alice:127.0.0.1")
    }

    @Test func rejectsNonUserIds() {
        #expect(MatrixUserID.parse("alice") == nil)
        #expect(MatrixUserID.parse("@alice") == nil)
        #expect(MatrixUserID.parse("@:example.org") == nil)
        #expect(MatrixUserID.parse("@alice:") == nil)
        #expect(MatrixUserID.parse("@al ice:example.org") == nil)
        #expect(MatrixUserID.parse("#room:example.org") == nil)
        #expect(MatrixUserID.parse("@alice:exa mple.org") == nil)
        #expect(MatrixUserID.parse("@alice:example.org:port") == nil)
        #expect(MatrixUserID.parse("") == nil)
    }

    @Test func serverNameOfUserId() {
        #expect(MatrixUserID.serverName(of: "@alice:example.org:8448") == "example.org:8448")
        #expect(MatrixUserID.serverName(of: "alice") == nil)
    }
}

struct NewChatResultsTests {
    private let alice = NewChatPerson(userId: "@alice:example.org", displayName: "Alice")
    private let bob = NewChatPerson(userId: "@bob:example.org", displayName: "Bob")
    private let me = "@patrick:example.org"

    @Test func plainQueryKeepsServerOrder() {
        let rows = NewChatResults.assemble(
            query: "a", resolvedProfile: nil, searchResults: [alice, bob],
            ownUserId: me, selectedUserIds: []
        )
        #expect(rows == [alice, bob])
    }

    @Test func exactIdWithoutProfileOrResultIsOfferedBare() {
        // The directory hides users you share no room with, and bots may not
        // expose a profile: the typed ID must still be startable.
        let rows = NewChatResults.assemble(
            query: " @slackbot:davlin.io ", resolvedProfile: nil, searchResults: [alice],
            ownUserId: me, selectedUserIds: []
        )
        #expect(rows == [NewChatPerson(userId: "@slackbot:davlin.io"), alice])
    }

    @Test func exactIdUsesResolvedProfileAndDeduplicates() {
        let resolved = NewChatPerson(userId: bob.userId, displayName: "Bob Resolved")
        let rows = NewChatResults.assemble(
            query: bob.userId, resolvedProfile: resolved, searchResults: [alice, bob],
            ownUserId: me, selectedUserIds: []
        )
        #expect(rows == [resolved, alice])
    }

    @Test func exactIdFallsBackToMatchingSearchResult() {
        let rows = NewChatResults.assemble(
            query: bob.userId, resolvedProfile: nil, searchResults: [alice, bob],
            ownUserId: me, selectedUserIds: []
        )
        #expect(rows == [bob, alice])
    }

    @Test func staleResolvedProfileIsIgnored() {
        // A profile resolved for an earlier query must not label this one.
        let rows = NewChatResults.assemble(
            query: bob.userId, resolvedProfile: alice, searchResults: [],
            ownUserId: me, selectedUserIds: []
        )
        #expect(rows == [NewChatPerson(userId: bob.userId)])
    }

    @Test func excludesOwnUserAndSelectedPeople() {
        let own = NewChatPerson(userId: me, displayName: "Me")
        let rows = NewChatResults.assemble(
            query: "e", resolvedProfile: nil, searchResults: [own, alice, bob],
            ownUserId: me, selectedUserIds: [alice.userId]
        )
        #expect(rows == [bob])
    }

    @Test func excludesOwnUserTypedAsExactId() {
        let rows = NewChatResults.assemble(
            query: me, resolvedProfile: nil, searchResults: [],
            ownUserId: me, selectedUserIds: []
        )
        #expect(rows.isEmpty)
    }

    @Test func deduplicatesRepeatedSearchResults() {
        let rows = NewChatResults.assemble(
            query: "a", resolvedProfile: nil, searchResults: [alice, alice, bob],
            ownUserId: nil, selectedUserIds: []
        )
        #expect(rows == [alice, bob])
    }
}

struct NewChatStartTests {
    private let alice = NewChatPerson(userId: "@alice:example.org")
    private let bob = NewChatPerson(userId: "@bob:example.org")

    @Test func directNeedsExactlyOnePerson() {
        #expect(NewChatStartRequest.make(mode: .direct, selected: [], groupName: "", isEncrypted: true) == nil)
        #expect(NewChatStartRequest.make(mode: .direct, selected: [alice, bob], groupName: "", isEncrypted: true) == nil)
        #expect(
            NewChatStartRequest.make(mode: .direct, selected: [alice], groupName: "", isEncrypted: true)
                == .direct(userId: alice.userId)
        )
    }

    @Test func groupNeedsAtLeastOnePersonAndTrimsName() {
        #expect(NewChatStartRequest.make(mode: .group, selected: [], groupName: "Team", isEncrypted: true) == nil)
        #expect(
            NewChatStartRequest.make(mode: .group, selected: [alice, bob], groupName: "  Team ", isEncrypted: false)
                == .group(name: "Team", userIds: [alice.userId, bob.userId], isEncrypted: false)
        )
        #expect(
            NewChatStartRequest.make(mode: .group, selected: [alice], groupName: "   ", isEncrypted: true)
                == .group(name: nil, userIds: [alice.userId], isEncrypted: true)
        )
    }

    @Test func joinModeNeverStartsAChat() {
        #expect(NewChatStartRequest.make(mode: .join, selected: [alice], groupName: "", isEncrypted: true) == nil)
    }

    @Test func directReusesExistingRoom() {
        #expect(
            NewChatStartPlan.make(request: .direct(userId: alice.userId), existingDirectRoomId: "!dm:example.org")
                == .openRoom(roomId: "!dm:example.org")
        )
        #expect(
            NewChatStartPlan.make(request: .direct(userId: alice.userId), existingDirectRoomId: nil)
                == .createDirect(userId: alice.userId)
        )
    }

    @Test func groupAlwaysCreates() {
        let request = NewChatStartRequest.group(name: "Team", userIds: [alice.userId], isEncrypted: true)
        #expect(
            NewChatStartPlan.make(request: request, existingDirectRoomId: "!dm:example.org")
                == .createGroup(name: "Team", userIds: [alice.userId], isEncrypted: true)
        )
    }
}
