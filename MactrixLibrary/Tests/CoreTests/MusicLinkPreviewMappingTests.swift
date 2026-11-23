@testable import Core
import Foundation
import MatrixRustSDK
import Models
import Testing

/// MATRIX-219: the SDK's URL preview answer and errors, mapped to the JSON
/// body and `MusicLinkPreviewFailure` of the music link titles.
struct MusicLinkPreviewMappingTests {
    private static let trackJSON = """
    {"og:type": "music.song", "og:title": "Song", "og:description": "Artist · Album · Song · 2024"}
    """

    private func link(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    // MARK: Answer

    @Test func theAnswerIsTheJSONBody() throws {
        let data = try MusicLinkPreviewRead.json(from: Self.trackJSON)
        #expect(data == Data(Self.trackJSON.utf8))
        #expect(MusicLinkTitle.parse(data, kind: .song) == MusicLinkTitle(artist: "Artist", name: "Song"))
    }

    @Test func noAnswerIsNoPreview() {
        #expect(throws: MusicLinkPreviewFailure.noPreview) {
            try MusicLinkPreviewRead.json(from: nil)
        }
        #expect(throws: MusicLinkPreviewFailure.noPreview) {
            try MusicLinkPreviewRead.json(from: "")
        }
    }

    // MARK: Errors

    @Test func aMatrixErrorIsAnAnswerOfTheHomeserver() {
        let blocked = ClientError.MatrixApi(
            kind: .unknown,
            code: "M_UNKNOWN",
            msg: "URL blocked by url pattern blocklist entry",
            details: nil
        )
        let failure = MusicLinkPreviewRead.failure(for: blocked)
        #expect(failure == .homeserver(errcode: "M_UNKNOWN"))
        #expect(!failure.isTransient)
        #expect(!MusicLinkPreviewFailure.isTransient(failure))

        let forbidden = ClientError.MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "Forbidden", details: nil)
        #expect(MusicLinkPreviewRead.failure(for: forbidden) == .homeserver(errcode: "M_FORBIDDEN"))
    }

    @Test func aGenericErrorIsTransportAndDropsItsMessage() {
        let message = "error sending request for url "
            + "(https://matrix.example.org/_matrix/client/v1/media/preview_url?url=https%3A%2F%2Fopen.spotify.com)"
        let error = ClientError.Generic(msg: message, details: message)
        let failure = MusicLinkPreviewRead.failure(for: error)
        #expect(failure == .transport)
        #expect(failure.isTransient)
        let name = MusicLinkPreviewFailure.logName(of: failure)
        #expect(name == "transport")
        #expect(!name.contains("spotify"))
        #expect(!name.contains("matrix.example.org"))
    }

    @Test func anErrorOfAnotherTypeIsTransport() {
        #expect(MusicLinkPreviewRead.failure(for: URLError(.timedOut)) == .transport)
        #expect(MusicLinkPreviewRead.failure(for: CancellationError()) == .transport)
    }

    @Test func theLogNameOfAnAnswerIsItsCode() {
        let name = MusicLinkPreviewFailure.logName(of: MusicLinkPreviewFailure.homeserver(errcode: "M_UNKNOWN"))
        #expect(name == #"homeserver(errcode: "M_UNKNOWN")"#)
    }

    // MARK: Link

    @Test func anHTTPSLinkGoesAsItIs() throws {
        let link = try link("https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT")
        #expect(try MusicLinkPreviewRead.previewURL(of: link) == "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test func aLinkThatIsNotHTTPSIsRefused() throws {
        for string in ["http://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT", "spotify:track:4cOdK2wGLETKBW3PvgPWqT"] {
            let link = try link(string)
            #expect(throws: MusicLinkPreviewFailure.badLink) {
                try MusicLinkPreviewRead.previewURL(of: link)
            }
        }
    }
}
