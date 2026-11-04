import Testing
import Utils

/// MATRIX-75: what the New Chat join field accepts.
struct MatrixJoinTargetTests {
    private func parse(_ input: String) -> MatrixJoinTarget? {
        MatrixJoinTarget(parsing: input)
    }

    @Test func roomAlias() {
        #expect(parse(" #general:example.org ") == MatrixJoinTarget(roomIdOrAlias: "#general:example.org", viaServers: []))
    }

    @Test func roomIdRoutesThroughItsOwnServerByDefault() {
        #expect(parse("!abc:example.org") == MatrixJoinTarget(roomIdOrAlias: "!abc:example.org", viaServers: ["example.org"]))
    }

    @Test func roomIdWithViaServers() {
        #expect(
            parse("!abc:example.org?via=a.org&via=b.org")
                == MatrixJoinTarget(roomIdOrAlias: "!abc:example.org", viaServers: ["a.org", "b.org"])
        )
    }

    @Test func serverlessRoomIdHasNoDefaultVia() {
        #expect(parse("!opaqueV12Id") == MatrixJoinTarget(roomIdOrAlias: "!opaqueV12Id", viaServers: []))
    }

    @Test func matrixUris() {
        #expect(parse("matrix:r/general:example.org") == MatrixJoinTarget(roomIdOrAlias: "#general:example.org", viaServers: []))
        #expect(
            parse("matrix:roomid/abc:example.org?via=elsewhere.ca")
                == MatrixJoinTarget(roomIdOrAlias: "!abc:example.org", viaServers: ["elsewhere.ca"])
        )
        #expect(parse("matrix:u/alice:example.org") == nil)
    }

    @Test func matrixToLinks() {
        #expect(
            parse("https://matrix.to/#/#general:example.org")
                == MatrixJoinTarget(roomIdOrAlias: "#general:example.org", viaServers: [])
        )
        #expect(
            parse("https://matrix.to/#/%23general%3Aexample.org")
                == MatrixJoinTarget(roomIdOrAlias: "#general:example.org", viaServers: [])
        )
        #expect(
            parse("https://matrix.to/#/!abc:example.org/$event?via=a.org")
                == MatrixJoinTarget(roomIdOrAlias: "!abc:example.org", viaServers: ["a.org"])
        )
        #expect(parse("https://matrix.to/#/@alice:example.org") == nil)
    }

    @Test func rejectsOtherInput() {
        #expect(parse("") == nil)
        #expect(parse("general") == nil)
        #expect(parse("#general") == nil)
        #expect(parse("#:example.org") == nil)
        #expect(parse("!") == nil)
        #expect(parse("https://example.org/#/#general:example.org") == nil)
    }
}
