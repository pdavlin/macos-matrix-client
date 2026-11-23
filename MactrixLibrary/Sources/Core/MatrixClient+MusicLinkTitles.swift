import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The SDK side of the music link titles (MATRIX-191).
///
/// The rules live in `Models` (`MusicLinkTitleStore`, `MusicLinkTitle`),
/// where they are unit-tested. The read is the SDK's
/// `Client.getUrlPreview(url:ts:)` (MATRIX-219), which replaced the raw
/// request that the contract §11 row of 2026-11-18 granted. This file gives
/// the shared store that read and its cache file in the session's caches.
extension MatrixClient {
    /// Gives `MusicLinkTitleStore.shared` this session's preview read and
    /// cache file, and loads the file, so the first layout of a row has the
    /// titles that an earlier launch read. Call it once the SDK client
    /// exists, before a timeline shows.
    func configureMusicLinkTitles() {
        guard let sdkClient: ClientProtocol = client else { return }
        MusicLinkTitleStore.shared.configure(
            cacheFile: URL.sessionCaches(for: storeID).appending(component: "MusicLinkTitles.json"),
            fetch: { url in
                try await MusicLinkPreviewRead.preview(of: url, client: sdkClient)
            },
            report: { line in
                // A 403 (previews off on the server) is an expected answer,
                // and the store keeps it for an hour: debug level only.
                Logger.matrixClient.debug("\(line, privacy: .public)")
            }
        )
    }

    /// Stops the reads and drops the titles on sign-out, before the caches
    /// folder is removed, so no write makes the file again.
    func resetMusicLinkTitles() async {
        MusicLinkTitleStore.shared.configure(cacheFile: nil, fetch: nil)
        await MusicLinkTitleStore.shared.waitForCacheWrite()
    }
}

/// The preview read of `MusicLinkTitleStore` (MATRIX-219): the SDK's URL
/// preview call, with its answer and its errors mapped to the JSON body and
/// `Models.MusicLinkPreviewFailure`. The SDK sends the request with the
/// session's token to the session's homeserver, so the app holds no token
/// and no HTTP transport for it.
enum MusicLinkPreviewRead {
    /// The URL preview JSON of `link`, an object of Open Graph keys
    /// (`MusicLinkTitle.parse`).
    ///
    /// - Throws: `MusicLinkPreviewFailure` only.
    static func preview(of link: URL, client: ClientProtocol) async throws -> Data {
        let url = try previewURL(of: link)
        let answer: String?
        do {
            // `ts` is deprecated since Matrix 1.11: the SDK says to pass nil.
            answer = try await client.getUrlPreview(url: url, ts: nil)
        } catch {
            throw failure(for: error)
        }
        return try json(from: answer)
    }

    /// The URL the SDK previews: the link as it is. Only an `https` link
    /// goes to the homeserver.
    ///
    /// - Throws: `MusicLinkPreviewFailure.badLink` for any other link.
    static func previewURL(of link: URL) throws -> String {
        guard link.scheme?.lowercased() == "https" else { throw MusicLinkPreviewFailure.badLink }
        return link.absoluteString
    }

    /// The JSON body of the SDK's answer.
    ///
    /// - Throws: `MusicLinkPreviewFailure.noPreview` if the homeserver gave
    ///   no preview.
    static func json(from answer: String?) throws -> Data {
        guard let answer, !answer.isEmpty else { throw MusicLinkPreviewFailure.noPreview }
        return Data(answer.utf8)
    }

    /// The failure for an error of the SDK call: the Matrix error code of an
    /// answer of the homeserver, else `transport`. A `ClientError.Generic`
    /// is a network error or an HTTP error with no Matrix error body. Its
    /// message can hold the URL, so it is not kept.
    static func failure(for error: Error) -> MusicLinkPreviewFailure {
        if case let .MatrixApi(_, code, _, _) = error as? ClientError {
            return .homeserver(errcode: code)
        }
        return .transport
    }
}
