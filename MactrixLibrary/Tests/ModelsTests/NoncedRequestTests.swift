import Models
import Testing

/// MATRIX-138: the reaction picker request from a row to the timeline
/// controller. The same message can be requested twice, and a controller
/// made later does not replay an old request.
struct NoncedRequestTests {
    @Test func startsEmpty() {
        let channel = NoncedRequestChannel<String>()
        #expect(channel.latest == nil)
    }

    @Test func eachSendGetsTheNextNonce() {
        var channel = NoncedRequestChannel<String>()
        channel.send("a")
        #expect(channel.latest == NoncedRequest(payload: "a", nonce: 1))
        channel.send("b")
        #expect(channel.latest == NoncedRequest(payload: "b", nonce: 2))
    }

    @Test func theSamePayloadTwiceIsTwoRequests() {
        var channel = NoncedRequestChannel<String>()
        var cursor = NoncedRequestCursor(startingAt: channel.latest)

        channel.send("a")
        let first = channel.latest
        channel.send("a")
        let second = channel.latest

        #expect(first != second)
        #expect(cursor.take(first) == "a")
        #expect(cursor.take(second) == "a")
    }

    @Test func aRequestIsTakenOnce() {
        var channel = NoncedRequestChannel<String>()
        var cursor = NoncedRequestCursor(startingAt: channel.latest)

        channel.send("a")
        #expect(cursor.take(channel.latest) == "a")
        #expect(cursor.take(channel.latest) == nil)
        #expect(cursor.handledNonce == 1)
    }

    @Test func nilIsNoRequest() {
        var cursor = NoncedRequestCursor(startingAt: NoncedRequest<String>?.none)
        #expect(cursor.take(NoncedRequest<String>?.none) == nil)
        #expect(cursor.handledNonce == 0)
    }

    @Test func aCursorMadeLaterSkipsTheEarlierRequests() {
        var channel = NoncedRequestChannel<String>()
        channel.send("a")
        channel.send("b")

        var cursor = NoncedRequestCursor(startingAt: channel.latest)
        #expect(cursor.take(channel.latest) == nil)

        channel.send("c")
        #expect(cursor.take(channel.latest) == "c")
    }

    @Test func anOlderRequestIsIgnored() {
        var channel = NoncedRequestChannel<String>()
        var cursor = NoncedRequestCursor(startingAt: channel.latest)
        channel.send("a")
        let older = channel.latest
        channel.send("b")

        #expect(cursor.take(channel.latest) == "b")
        #expect(cursor.take(older) == nil)
    }
}
