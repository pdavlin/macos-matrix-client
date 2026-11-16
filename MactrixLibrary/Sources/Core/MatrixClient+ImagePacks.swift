import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The SDK and network side of the image packs (MATRIX-155): the custom
/// emoji of a chat's workspace, for the reaction picker.
///
/// The rules and the parser live in `Models` (`ImagePackStore`, `ImagePack`),
/// where they are unit-tested. The one HTTP request is
/// `Models.RoomStateReader`, the bounded exception to hard rule 1 in the
/// contract §11 rows of 2026-11-13 and 2026-11-16. This file gives it its
/// transport and the session's homeserver URL and access token
/// (`RoomStateTransport`), for the image packs and for
/// `MatrixClient+OwnServiceProfile.swift`.
public extension MatrixClient {
    /// Loads the image packs of the room's parent spaces into `imagePacks`
    /// and returns at once. Call it when a chat opens, when the picker opens,
    /// and when the composer's emoji list opens: the store reads the
    /// homeserver only when its last good read of the space is older than
    /// `ImagePackStore.refreshInterval` (MATRIX-161). Does nothing after a
    /// sign-out.
    ///
    /// - Parameters:
    ///   - roomId: The room of the chat. In a merged chat, the member room.
    ///   - refresh: Reads the homeserver again.
    func loadImagePacks(forRoom roomId: String, refresh: Bool = false) {
        // MATRIX-165: the same triggers load the own image of the room's
        // workspace. The store reads only when its answer is absent or old.
        loadOwnServiceAvatar(forRoom: roomId)
        guard let source = imagePackSource else { return }
        Task { await imagePacks.load(roomId: roomId, refresh: refresh, from: source) }
    }

    /// The "Refresh Custom Emoji" command (MATRIX-161): reads the state of
    /// the room's workspace now and returns at once. The picker shows
    /// `imagePacks.refreshStatusByRoom[roomId]`: busy, then the outcome for
    /// `refreshResultDuration`. Does nothing for a room with no parent
    /// space, and after a sign-out.
    ///
    /// - Parameter roomId: The room of the chat. In a merged chat, the
    ///   member room.
    func refreshImagePacks(forRoom roomId: String) {
        guard let source = imagePackSource else { return }
        Task {
            guard await imagePacks.refresh(roomId: roomId, from: source) != nil else { return }
            try? await Task.sleep(for: Self.refreshResultDuration)
            imagePacks.clearRefreshStatus(forRoom: roomId)
        }
    }

    /// How long the outcome of a refresh shows.
    static let refreshResultDuration: Duration = .seconds(4)

    /// Records the custom emoji that a message body of the room showed
    /// (MATRIX-161). The store keeps them for the room's workspace, apart
    /// from the imported pack, and makes no request.
    ///
    /// - Parameters:
    ///   - emoji: The emoji of the body, see `LearnedEmoji.emoji(name:url:)`.
    ///   - roomId: The room of the message.
    func learnEmoji(_ emoji: [ImagePackEmoji], inRoom roomId: String) {
        imagePacks.learn(emoji, roomId: roomId)
    }

    /// Where the store reads from, or nil after a sign-out.
    private var imagePackSource: ImagePackStore.Source? {
        guard let spaceService, let sdkClient: ClientProtocol = client else { return nil }
        let service: SpaceService = spaceService.spaceService
        return ImagePackStore.Source(
            cacheDirectory: URL.sessionCaches(for: storeID).appending(component: "ImagePacks"),
            parentSpaces: { [roomAccounts] roomId in
                let live = try await service.joinedParentsOfChild(childId: roomId)
                    .map { ImagePackStore.Space(id: $0.roomId, name: $0.displayName) }
                // MATRIX-170: the cached parents, until the SDK's space
                // graph is ready.
                return live.isEmpty
                    ? roomAccounts.launchParents(of: roomId).map { ImagePackStore.Space(id: $0.id, name: $0.name) }
                    : live
            },
            fetchState: { spaceId in
                try await RoomStateTransport.state(of: spaceId, client: sdkClient)
            },
            report: { line in
                Logger.matrixClient.error("image packs: \(line, privacy: .public)")
            }
        )
    }
}

/// The `URLSession` behind `RoomStateReader`, and the one place that reads
/// the session's access token for it.
///
/// The session is ephemeral, so the room state does not go into a URL cache
/// on disk, and it has no cookies. A redirect is not followed, so the
/// `Authorization` header goes only to the homeserver of the SDK session.
enum RoomStateTransport {
    /// The state of a room, read from the homeserver of the SDK session.
    ///
    /// - Parameters:
    ///   - roomId: A workspace space (image packs), or one direct chat of a
    ///     workspace (MATRIX-165). No other room: see `RoomStateReader`.
    ///   - client: The SDK client of the session.
    @MainActor
    static func state(of roomId: String, client: ClientProtocol) async throws -> Data {
        // The token stays in this function: it goes into the request header
        // and nowhere else.
        let session: Session = try client.session()
        return try await reader.state(
            of: roomId,
            homeserverURL: session.homeserverUrl,
            accessToken: session.accessToken
        )
    }

    private static let reader = RoomStateReader { request in
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
