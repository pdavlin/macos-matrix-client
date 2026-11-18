import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The SDK and network side of the music link titles (MATRIX-191).
///
/// The rules live in `Models` (`MusicLinkTitleStore`, `MusicLinkTitle`),
/// where they are unit-tested. The one HTTP request is
/// `Models.MusicLinkPreviewReader`, the second read outside the SDK, granted
/// by the contract §11 row of 2026-11-18. This file gives the shared store
/// its read, with the session's homeserver URL and access token, and its
/// cache file in the session's caches.
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
                try await MusicLinkPreviewTransport.preview(of: url, client: sdkClient)
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

/// The `URLSession` behind `MusicLinkPreviewReader`, and the one place that
/// reads the session's access token for it. It uses the ephemeral session of
/// `RoomStateTransport`: no URL cache on disk, no cookies, and no redirect,
/// so the `Authorization` header goes only to the homeserver of the SDK
/// session.
enum MusicLinkPreviewTransport {
    /// The URL preview JSON of `link`, read from the homeserver of the SDK
    /// session.
    @MainActor
    static func preview(of link: URL, client: ClientProtocol) async throws -> Data {
        // The token stays in this function: it goes into the request header
        // and nowhere else.
        let session: Session = try client.session()
        return try await reader.preview(
            of: link,
            homeserverURL: session.homeserverUrl,
            accessToken: session.accessToken
        )
    }

    private static let reader = MusicLinkPreviewReader { request in
        try await RoomStateTransport.session.data(for: request, delegate: RoomStateTransport.RefuseRedirects())
    }
}
