import Foundation
import MatrixRustSDK
import OSLog

/// The account's own profile image (MATRIX-163).
///
/// `ownAvatarUrl` is the one observable value for the account's global
/// avatar. The timeline's own-message fallback and the Account settings read
/// it; nothing calls the SDK per row. The SDK owns the upload, the removal,
/// and the profile requests.
public extension MatrixClient {
    /// Reads the account's avatar URL into `ownAvatarUrl`.
    ///
    /// - Parameter readsCache: when true, shows the SDK's cached URL first,
    ///   so a start without a network still has the last known avatar. Pass
    ///   false after a change: the cache can hold the old URL.
    func refreshOwnAvatar(readsCache: Bool = false) async {
        guard let sdkClient: ClientProtocol = client else { return }
        if readsCache, ownAvatarUrl == nil {
            do {
                ownAvatarUrl = try await Self.normalizedAvatarUrl(sdkClient.cachedAvatarUrl())
            } catch {
                Logger.matrixClient.error("failed to read the cached own avatar: \(String(describing: error), privacy: .public)")
            }
        }
        do {
            let url = try await Self.normalizedAvatarUrl(sdkClient.avatarUrl())
            if url != ownAvatarUrl {
                ownAvatarUrl = url
            }
        } catch {
            Logger.matrixClient.error("failed to read the own avatar: \(String(describing: error), privacy: .public)")
        }
    }

    /// Uploads `data` as the account's profile image, then refreshes
    /// `ownAvatarUrl`.
    func uploadOwnAvatar(mimeType: String, data: Data) async throws {
        guard let sdkClient: ClientProtocol = client else { return }
        try await sdkClient.uploadAvatar(mimeType: mimeType, data: data)
        await refreshOwnAvatar()
    }

    /// Removes the account's profile image, then refreshes `ownAvatarUrl`.
    func removeOwnAvatar() async throws {
        guard let sdkClient: ClientProtocol = client else { return }
        try await sdkClient.removeAvatar()
        ownAvatarUrl = nil
        await refreshOwnAvatar()
    }

    /// An empty URL is no avatar.
    private static func normalizedAvatarUrl(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return nil }
        return url
    }
}
