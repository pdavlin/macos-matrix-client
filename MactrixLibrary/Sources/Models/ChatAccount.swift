import Foundation

/// The account a bridged chat belongs to on its network (MATRIX-148): a Slack
/// workspace, read from the joined space the bridge puts the chat in.
///
/// Presentation only. The chat list draws the account's icon as the avatar
/// badge in place of the network's letter.
public struct ChatAccount: Hashable, Sendable {
    /// The account's name, for example "DevObsessed".
    public var name: String
    /// The `mxc://` URL of the account's icon, or nil when it has none.
    public var avatarUrl: String?

    public init(name: String, avatarUrl: String? = nil) {
        self.name = name
        self.avatarUrl = avatarUrl
    }

    /// The account among a room's parent spaces: the first space with a
    /// name that is not blank and is not the network's own name (a bridge's
    /// "Slack" space is the network, not an account).
    ///
    /// - Parameters:
    ///   - spaces: the joined spaces that hold the room.
    ///   - network: the room's network, or nil.
    public static func choose(from spaces: [ChatAccount], network: ChatListNetwork?) -> ChatAccount? {
        for space in spaces {
            let name = space.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if let network, name.caseInsensitiveCompare(network.displayName) == .orderedSame {
                continue
            }
            return ChatAccount(name: name, avatarUrl: space.avatarUrl)
        }
        return nil
    }
}

/// One avatar badge (MATRIX-148): a chat's network and its account. The
/// badge draws the account's icon when it has one, else the network's letter.
public struct ChatBadge: Hashable, Sendable {
    public var network: ChatListNetwork?
    public var account: ChatAccount?

    public init(network: ChatListNetwork?, account: ChatAccount? = nil) {
        self.network = network
        self.account = account
    }

    /// The badge draws something: a letter or an icon.
    public var isVisible: Bool {
        network != nil || account?.avatarUrl != nil
    }
}
