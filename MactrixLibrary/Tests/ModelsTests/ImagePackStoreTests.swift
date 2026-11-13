import Foundation
import Models
import Testing

/// MATRIX-155: the one request outside the SDK. A stub transport stands in
/// for the network.
struct ImagePackStateReaderTests {
    private static let token = "syt_secret_token"

    private func response(_ status: Int) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://matrix.example.org/"))
        return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
    }

    @Test func theRequestIsAnAuthenticatedGetOfTheRoomState() throws {
        let request = try ImagePackStateReader.request(
            roomId: "!space/id:example.org",
            homeserverURL: "https://matrix.example.org/",
            accessToken: Self.token
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString
            == "https://matrix.example.org/_matrix/client/v3/rooms/%21space%2Fid%3Aexample.org/state")
        #expect(request.allHTTPHeaderFields == ["Authorization": "Bearer \(Self.token)", "Accept": "application/json"])
        #expect(request.httpBody == nil)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func theRequestKeepsAHomeserverPathPrefixAndDropsItsQuery() throws {
        let request = try ImagePackStateReader.request(
            roomId: "!s:example.org",
            homeserverURL: "http://localhost:8008/base/?x=1#y",
            accessToken: Self.token
        )
        #expect(request.url?.absoluteString == "http://localhost:8008/base/_matrix/client/v3/rooms/%21s%3Aexample.org/state")
    }

    @Test func aHomeserverURLThatIsNotHTTPIsRefused() {
        for bad in ["", "matrix.example.org", "file:///etc/passwd", "ftp://example.org", "https://"] {
            #expect(throws: ImagePackStateReader.Failure.badHomeserverURL) {
                try ImagePackStateReader.request(roomId: "!s:example.org", homeserverURL: bad, accessToken: Self.token)
            }
        }
    }

    @Test func aGoodAnswerGivesTheBody() async throws {
        let ok = try response(200)
        let reader = ImagePackStateReader { request in
            #expect(request.url?.host() == "matrix.example.org")
            return (Data("[]".utf8), ok)
        }
        let body = try await reader.state(of: "!s:example.org", homeserverURL: "https://matrix.example.org", accessToken: Self.token)
        #expect(body == Data("[]".utf8))
    }

    @Test func anErrorStatusThrowsWithoutTheBodyOrTheToken() async throws {
        let forbidden = try response(403)
        let reader = ImagePackStateReader { _ in (Data("{\"errcode\":\"M_FORBIDDEN\"}".utf8), forbidden) }

        do {
            _ = try await reader.state(of: "!s:example.org", homeserverURL: "https://matrix.example.org", accessToken: Self.token)
            Issue.record("the read did not throw")
        } catch {
            #expect(error as? ImagePackStateReader.Failure == .status(403))
            let text = String(describing: error)
            #expect(!text.contains(Self.token))
            #expect(!text.contains("M_FORBIDDEN"))
        }
    }

    @Test func anAnswerThatIsNotHTTPThrows() async throws {
        let url = try #require(URL(string: "https://matrix.example.org/"))
        let plain = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let reader = ImagePackStateReader { _ in (Data(), plain) }

        await #expect(throws: ImagePackStateReader.Failure.notHTTP) {
            try await reader.state(of: "!s:example.org", homeserverURL: "https://matrix.example.org", accessToken: Self.token)
        }
    }
}

/// MATRIX-155: the store reads the cache first and the homeserver at most
/// once per space per session. Every source is a stub: no SDK, no network.
@MainActor
struct ImagePackStoreTests {
    private struct ReadFailed: Error {}

    /// The stubs behind a `Source`, with call counts.
    @MainActor
    private final class Backend {
        var parents: [String: [ImagePackStore.Space]] = [:]
        var states: [String: Result<Data, Error>] = [:]
        var parentReads = 0
        var stateReads: [String] = []
        var reports: [String] = []
        let cacheDirectory: URL?

        init(cacheDirectory: URL? = nil) {
            self.cacheDirectory = cacheDirectory
        }

        var source: ImagePackStore.Source {
            ImagePackStore.Source(
                cacheDirectory: cacheDirectory,
                parentSpaces: { roomId in
                    self.parentReads += 1
                    return self.parents[roomId] ?? []
                },
                fetchState: { spaceId in
                    self.stateReads.append(spaceId)
                    return try (self.states[spaceId] ?? .failure(ReadFailed())).get()
                },
                report: { self.reports.append($0) }
            )
        }
    }

    private static let space = ImagePackStore.Space(id: "!space:example.org", name: "Acme")
    private static let room = "!channel:example.org"

    private static func state(shortcodes: [String], displayName: String? = "Acme emojis") -> Data {
        let images = shortcodes.map { "\"\($0)\": {\"url\": \"mxc://example.org/\($0)\"}" }.joined(separator: ", ")
        let pack = displayName.map { "{\"display_name\": \"\($0)\"}" } ?? "{}"
        return Data("""
        [{"type": "m.room.image_pack", "state_key": "acme", "content": {"images": {\(images)}, "pack": \(pack)}}]
        """.utf8)
    }

    private func backend(cache: Bool = false) throws -> Backend {
        var directory: URL?
        if cache {
            let url = FileManager.default.temporaryDirectory.appending(component: "ImagePackStoreTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            directory = url
        }
        let backend = Backend(cacheDirectory: directory)
        backend.parents[Self.room] = [Self.space]
        backend.states[Self.space.id] = .success(Self.state(shortcodes: ["shipit", "parrot"]))
        return backend
    }

    @Test func loadsThePackOfTheRoomsParentSpace() async throws {
        let backend = try backend()
        let store = ImagePackStore()
        #expect(store.packs(forRoom: Self.room).isEmpty)

        await store.load(roomId: Self.room, from: backend.source)

        let packs = store.packs(forRoom: Self.room)
        #expect(packs.map(\.displayName) == ["Acme emojis"])
        #expect(packs.first?.emoji.map(\.shortcode) == ["parrot", "shipit"])
        #expect(store.packs(forRoom: "!other:example.org").isEmpty)
        #expect(backend.reports.isEmpty)
    }

    @Test func aPackWithoutANameTakesTheWorkspaceName() async throws {
        let backend = try backend()
        backend.states[Self.space.id] = .success(Self.state(shortcodes: ["shipit"], displayName: nil))
        let store = ImagePackStore()

        await store.load(roomId: Self.room, from: backend.source)

        #expect(store.packs(forRoom: Self.room).map(\.displayName) == ["Acme"])
    }

    @Test func readsTheHomeserverOncePerSpacePerSession() async throws {
        let backend = try backend()
        backend.parents["!second:example.org"] = [Self.space]
        let store = ImagePackStore()

        await store.load(roomId: Self.room, from: backend.source)
        await store.load(roomId: Self.room, from: backend.source)
        await store.load(roomId: "!second:example.org", from: backend.source)

        #expect(backend.stateReads == [Self.space.id])
        // Each room's parents are read once.
        #expect(backend.parentReads == 2)
        #expect(store.packs(forRoom: "!second:example.org").count == 1)
    }

    @Test func aRefreshReadsTheHomeserverAgain() async throws {
        let backend = try backend()
        let store = ImagePackStore()
        await store.load(roomId: Self.room, from: backend.source)

        backend.states[Self.space.id] = .success(Self.state(shortcodes: ["new"]))
        await store.load(roomId: Self.room, refresh: true, from: backend.source)

        #expect(backend.stateReads.count == 2)
        #expect(store.packs(forRoom: Self.room).first?.emoji.map(\.shortcode) == ["new"])
    }

    @Test func aCacheHitShowsThePackBeforeTheHomeserverAnswers() async throws {
        let backend = try backend(cache: true)
        await ImagePackStore().load(roomId: Self.room, from: backend.source)
        let directory = try #require(backend.cacheDirectory)
        let file = ImagePackStore.cacheFile(for: Self.space.id, in: directory)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(file.lastPathComponent == "%21space%3Aexample%2Eorg.json")

        // A new session: the homeserver read fails, the cache answers.
        backend.states[Self.space.id] = .failure(ReadFailed())
        let store = ImagePackStore()
        await store.load(roomId: Self.room, from: backend.source)

        #expect(store.packs(forRoom: Self.room).first?.emoji.map(\.shortcode) == ["parrot", "shipit"])
        #expect(backend.reports.count == 1)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func theCacheFileHoldsThePacksOnly() async throws {
        let backend = try backend(cache: true)
        await ImagePackStore().load(roomId: Self.room, from: backend.source)
        let directory = try #require(backend.cacheDirectory)

        let text = try String(contentsOf: ImagePackStore.cacheFile(for: Self.space.id, in: directory), encoding: .utf8)
        #expect(text.contains("shipit"))
        #expect(!text.contains("m.room.image_pack"))
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func aFailedReadKeepsThePackInUseAndIsReported() async throws {
        let backend = try backend()
        let store = ImagePackStore()
        await store.load(roomId: Self.room, from: backend.source)

        backend.states[Self.space.id] = .failure(ImagePackStateReader.Failure.status(502))
        await store.load(roomId: Self.room, refresh: true, from: backend.source)

        #expect(store.packs(forRoom: Self.room).first?.emoji.map(\.shortcode) == ["parrot", "shipit"])
        #expect(backend.reports == ["failed to read the image packs of !space:example.org: status(502)"])
    }

    @Test func aMalformedAnswerKeepsThePackInUse() async throws {
        let backend = try backend()
        let store = ImagePackStore()
        await store.load(roomId: Self.room, from: backend.source)

        backend.states[Self.space.id] = .success(Data("{\"errcode\": \"M_UNKNOWN\"}".utf8))
        await store.load(roomId: Self.room, refresh: true, from: backend.source)

        #expect(store.packs(forRoom: Self.room).count == 1)
        #expect(backend.reports.count == 1)
    }

    @Test func aSpaceGetsAFewFailedReadsPerSessionThenNoMore() async throws {
        let backend = try backend()
        backend.states[Self.space.id] = .failure(ReadFailed())
        let store = ImagePackStore()

        for _ in 0 ..< ImagePackStore.maxFailedReads + 3 {
            await store.load(roomId: Self.room, from: backend.source)
        }

        #expect(backend.stateReads.count == ImagePackStore.maxFailedReads)
        #expect(store.packs(forRoom: Self.room).isEmpty)
    }

    @Test func anEmptyParentAnswerIsAskedAgain() async throws {
        let backend = try backend()
        backend.parents[Self.room] = []
        let store = ImagePackStore()

        // The SDK's space graph is not ready: no parent, nothing kept.
        await store.load(roomId: Self.room, from: backend.source)
        #expect(backend.parentReads == 1)
        #expect(backend.stateReads.isEmpty)
        #expect(store.spacesByRoom[Self.room] == nil)

        backend.parents[Self.room] = [Self.space]
        await store.load(roomId: Self.room, from: backend.source)

        #expect(backend.parentReads == 2)
        #expect(store.packs(forRoom: Self.room).count == 1)
    }

    @Test func aFailedParentReadIsReportedAndAskedAgain() async throws {
        let backend = try backend()
        let store = ImagePackStore()
        var source = backend.source
        source = ImagePackStore.Source(
            cacheDirectory: nil,
            parentSpaces: { _ in throw ReadFailed() },
            fetchState: source.fetchState,
            report: source.report
        )

        await store.load(roomId: Self.room, from: source)
        #expect(backend.reports.count == 1)
        #expect(backend.stateReads.isEmpty)

        await store.load(roomId: Self.room, from: backend.source)
        #expect(store.packs(forRoom: Self.room).count == 1)
    }

    @Test func aSpaceWithNoPackHasAnEmptyListAndShowsNothing() async throws {
        let backend = try backend()
        backend.states[Self.space.id] = .success(Data("[]".utf8))
        let store = ImagePackStore()

        await store.load(roomId: Self.room, from: backend.source)

        #expect(store.packs(forRoom: Self.room).isEmpty)
        #expect(store.packsBySpace[Self.space.id] == [])
        #expect(backend.reports.isEmpty)
    }
}
