import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The SDK and network side of the image packs (MATRIX-155): the custom
/// emoji of a chat's workspace, for the reaction picker.
///
/// The rules and the parser live in `Models` (`ImagePackStore`, `ImagePack`),
/// where they are unit-tested. The one HTTP request is
/// `Models.ImagePackStateReader`, the bounded exception to hard rule 1 in the
/// contract §11 row of 2026-11-13. This file gives it its transport and the
/// session's homeserver URL and access token.
public extension MatrixClient {
    /// Loads the image packs of the room's parent spaces into `imagePacks`
    /// and returns at once. Call it when a chat opens and when the picker
    /// opens: the store reads the homeserver at most once per space per
    /// session. Does nothing after a sign-out.
    ///
    /// - Parameters:
    ///   - roomId: The room of the chat. In a merged chat, the member room.
    ///   - refresh: Reads the homeserver again.
    func loadImagePacks(forRoom roomId: String, refresh: Bool = false) {
        guard let spaceService, let sdkClient: ClientProtocol = client else { return }
        let service: SpaceService = spaceService.spaceService
        let source = ImagePackStore.Source(
            cacheDirectory: URL.sessionCaches(for: storeID).appending(component: "ImagePacks"),
            parentSpaces: { roomId in
                try await service.joinedParentsOfChild(childId: roomId)
                    .map { ImagePackStore.Space(id: $0.roomId, name: $0.displayName) }
            },
            fetchState: { spaceId in
                // The token stays in this closure: it goes into the request
                // header and nowhere else.
                let session: Session = try sdkClient.session()
                return try await ImagePackTransport.reader.state(
                    of: spaceId,
                    homeserverURL: session.homeserverUrl,
                    accessToken: session.accessToken
                )
            },
            report: { line in
                Logger.matrixClient.error("image packs: \(line, privacy: .public)")
            }
        )
        Task { await imagePacks.load(roomId: roomId, refresh: refresh, from: source) }
    }
}

/// The `URLSession` behind `ImagePackStateReader`.
///
/// The session is ephemeral, so the room state does not go into a URL cache
/// on disk, and it has no cookies. A redirect is not followed, so the
/// `Authorization` header goes only to the homeserver of the SDK session.
private enum ImagePackTransport {
    static let reader = ImagePackStateReader { request in
        try await session.data(for: request, delegate: RefuseRedirects())
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _: URLSession,
            task _: URLSessionTask,
            willPerformHTTPRedirection _: HTTPURLResponse,
            newRequest _: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }
}
