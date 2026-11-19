import Foundation
@testable import Models
import Testing

/// MATRIX-203: the body link router and what a Matrix link opens.
struct MatrixLinkRouteTests {
    private static let roomId = "!dreamteam:davlin.io"
    private static let eventId = "$event"
    private static let address = "https://matrix.to/#/!dreamteam:davlin.io/$event?via=davlin.io"
    private static let roomLink = MatrixLink.room(.id(roomId), eventId: nil, via: [])
    private static let eventLink = MatrixLink.room(.id(roomId), eventId: eventId, via: ["davlin.io"])
    private static let aliasLink = MatrixLink.room(.alias("#general:davlin.io"), eventId: nil, via: [])
    private static let userLink = MatrixLink.user(id: "@seth:davlin.io")
    private static let merged = MergedChatDocument(merges: [
        MergedChat(id: "m-seth", name: "Seth", rooms: ["!slack:davlin.io", roomId]),
    ])

    private static func plan(
        _ link: MatrixLink,
        _ facts: MatrixLinkFacts,
        document: MergedChatDocument = MergedChatDocument()
    ) -> MatrixLinkPlan {
        MatrixLinkPlan.make(link: link, address: address, facts: facts, document: document)
    }

    // MARK: Router

    @Test func matrixLinkGoesToTheApp() {
        #expect(BodyLinkRoute.route(isPlainClick: true, matrixLink: Self.eventLink, isPostPeekLink: false) == .matrix(Self.eventLink))
    }

    @Test func postPeekLinkStillGoesToThePeek() {
        #expect(BodyLinkRoute.route(isPlainClick: true, matrixLink: nil, isPostPeekLink: true) == .postPeek)
    }

    @Test func parseFailureGoesToTheBrowser() {
        #expect(BodyLinkRoute.route(isPlainClick: true, matrixLink: nil, isPostPeekLink: false) == .browser)
    }

    @Test(arguments: [true, false])
    func modifierClickGoesToTheBrowser(isPostPeekLink: Bool) {
        #expect(BodyLinkRoute.route(isPlainClick: false, matrixLink: Self.eventLink, isPostPeekLink: isPostPeekLink) == .browser)
        #expect(BodyLinkRoute.route(isPlainClick: false, matrixLink: nil, isPostPeekLink: isPostPeekLink) == .browser)
    }

    // MARK: Rooms

    @Test func joinedRoomByIdOpens() {
        let plan = Self.plan(Self.roomLink, MatrixLinkFacts(roomId: Self.roomId, isJoined: true))
        #expect(plan == .open(.room(Self.roomId), focus: nil))
    }

    @Test func joinedRoomByAliasOpensTheResolvedRoom() {
        let plan = Self.plan(Self.aliasLink, MatrixLinkFacts(roomId: "!general:davlin.io", isJoined: true))
        #expect(plan == .open(.room("!general:davlin.io"), focus: nil))
    }

    @Test func aliasThatDoesNotResolveOpensTheJoinFlow() {
        let plan = Self.plan(Self.aliasLink, MatrixLinkFacts())
        #expect(plan == .newChat(.join, .joinAddress(Self.address)))
    }

    @Test func roomNotJoinedOpensTheJoinFlowWithTheLink() {
        let plan = Self.plan(Self.eventLink, MatrixLinkFacts(roomId: Self.roomId, isJoined: false))
        #expect(plan == .newChat(.join, .joinAddress(Self.address)))
    }

    @Test func eventInARoomOpensTheRoomAndShowsTheEvent() {
        let plan = Self.plan(Self.eventLink, MatrixLinkFacts(roomId: Self.roomId, isJoined: true))
        #expect(plan == .open(.room(Self.roomId), focus: MatrixLinkEventFocus(roomId: Self.roomId, eventId: Self.eventId)))
    }

    @Test func threadReplyOpensTheThreadPanelOnItsRoot() {
        let plan = Self.plan(Self.eventLink, MatrixLinkFacts(roomId: Self.roomId, isJoined: true, threadRootId: "$root"))
        let focus = MatrixLinkEventFocus(roomId: Self.roomId, eventId: Self.eventId, threadRootId: "$root")
        #expect(plan == .open(.room(Self.roomId), focus: focus))
    }

    @Test func threadRootItselfStaysInTheMainTimeline() {
        let link = MatrixLink.room(.id(Self.roomId), eventId: "$root", via: [])
        let plan = Self.plan(link, MatrixLinkFacts(roomId: Self.roomId, isJoined: true, threadRootId: "$root"))
        #expect(plan == .open(.room(Self.roomId), focus: MatrixLinkEventFocus(roomId: Self.roomId, eventId: "$root")))
    }

    // MARK: Merged chats

    @Test func mergedMemberOpensTheMergedChat() {
        let plan = Self.plan(Self.roomLink, MatrixLinkFacts(roomId: Self.roomId, isJoined: true), document: Self.merged)
        #expect(plan == .open(.merged("m-seth"), focus: nil))
    }

    @Test func eventInAMergedMemberShowsTheEventInTheMergedChat() {
        let plan = Self.plan(Self.eventLink, MatrixLinkFacts(roomId: Self.roomId, isJoined: true), document: Self.merged)
        #expect(plan == .open(.merged("m-seth"), focus: MatrixLinkEventFocus(roomId: Self.roomId, eventId: Self.eventId)))
    }

    @Test func threadReplyInAMergedMemberShowsTheThreadRoot() {
        let facts = MatrixLinkFacts(roomId: Self.roomId, isJoined: true, threadRootId: "$root")
        let plan = Self.plan(Self.eventLink, facts, document: Self.merged)
        #expect(plan == .open(.merged("m-seth"), focus: MatrixLinkEventFocus(roomId: Self.roomId, eventId: "$root")))
    }

    // MARK: Users

    @Test func userWithADirectRoomOpensIt() {
        let plan = Self.plan(Self.userLink, MatrixLinkFacts(directRoomId: "!dm:davlin.io"))
        #expect(plan == .open(.room("!dm:davlin.io"), focus: nil))
    }

    @Test func userWithAMergedDirectRoomOpensTheMergedChat() {
        let plan = Self.plan(Self.userLink, MatrixLinkFacts(directRoomId: Self.roomId), document: Self.merged)
        #expect(plan == .open(.merged("m-seth"), focus: nil))
    }

    @Test func userWithoutADirectRoomOpensNewChat() {
        let plan = Self.plan(Self.userLink, MatrixLinkFacts())
        #expect(plan == .newChat(.direct, .person(NewChatPerson(userId: "@seth:davlin.io"))))
    }

    // MARK: Windows

    @Test func mainWindowOpensEveryLink() {
        for link in [Self.roomLink, Self.eventLink, Self.aliasLink, Self.userLink] {
            #expect(MatrixLinkPlan.opens(link, inWindowOf: nil))
        }
    }

    @Test func roomWindowOpensOnlyLinksToItsOwnRoom() {
        #expect(MatrixLinkPlan.opens(Self.eventLink, inWindowOf: Self.roomId))
        #expect(!MatrixLinkPlan.opens(Self.eventLink, inWindowOf: "!other:davlin.io"))
        #expect(!MatrixLinkPlan.opens(Self.aliasLink, inWindowOf: Self.roomId))
        #expect(!MatrixLinkPlan.opens(Self.userLink, inWindowOf: Self.roomId))
    }
}
