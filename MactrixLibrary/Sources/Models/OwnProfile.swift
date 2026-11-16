import Foundation

/// The signed-in account's own profile, as the settings draw it (MATRIX-163).
public struct OwnProfile: UserProfile, Equatable, Sendable {
    public let userId: String
    public let displayName: String?
    /// The account's global profile image, an `mxc://` URL. Nil without one.
    public let avatarUrl: String?

    public init(userId: String, displayName: String? = nil, avatarUrl: String? = nil) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

/// Which avatar a message's profile row draws (MATRIX-163, MATRIX-165).
public enum MessageAvatarRule {
    /// Picks the avatar URL for a message's sender, in this order:
    ///
    /// 1. For an own message only: the user's profile image on the service
    ///    of the chat's workspace (the Slack image of that workspace), when
    ///    one is known (`OwnServiceAvatarStore`).
    /// 2. The sender's room member avatar, when the member profile has one.
    /// 3. For an own message only: the account's global profile avatar. A
    ///    room member profile can lack the image the account has, for example
    ///    in a bridged room, or while the member profile is not loaded.
    /// 4. Nil: the row draws initials.
    ///
    /// Another user never takes the service image or the account's avatar.
    /// An empty URL counts as no avatar.
    ///
    /// - Parameters:
    ///   - serviceAvatarUrl: the avatar of the user's own bridge ghost in
    ///     the workspace of the message's room. Nil when none is known.
    ///   - memberAvatarUrl: the avatar of the sender's profile in the room.
    ///   - accountAvatarUrl: the signed-in account's global profile avatar.
    ///   - isOwn: whether the signed-in account sent the message.
    public static func avatarUrl(
        serviceAvatarUrl: String? = nil,
        memberAvatarUrl: String?,
        accountAvatarUrl: String?,
        isOwn: Bool
    ) -> String? {
        if isOwn, let serviceAvatarUrl, !serviceAvatarUrl.isEmpty {
            return serviceAvatarUrl
        }
        if let memberAvatarUrl, !memberAvatarUrl.isEmpty {
            return memberAvatarUrl
        }
        if isOwn, let accountAvatarUrl, !accountAvatarUrl.isEmpty {
            return accountAvatarUrl
        }
        return nil
    }
}

/// The limits of a profile image the app uploads (MATRIX-163).
public enum ProfileImageLimit {
    /// The largest side, in pixels.
    public static let maxPixelSize = 512
}
