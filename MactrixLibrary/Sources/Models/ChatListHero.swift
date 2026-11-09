import Foundation

/// One of a room's heroes, as the chat-list avatar draws it (MATRIX-129).
///
/// The Matrix spec's heroes are up to five members the server picks to name
/// and picture a room without a name or avatar of its own. They never include
/// the user. The Core layer copies each SDK `RoomHero` into this value, so the
/// avatar views and their tests need no SDK type.
public struct ChatListHero: Equatable, Hashable, Identifiable, Sendable {
    /// The full Matrix user ID, for example `@alice:example.org`.
    public var userId: String
    /// The member's display name, when the server knows one.
    public var displayName: String?
    /// The `mxc://` URL of the member's avatar, when they set one.
    public var avatarUrl: String?

    public var id: String {
        userId
    }

    public init(userId: String, displayName: String? = nil, avatarUrl: String? = nil) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }

    /// Localparts of the mautrix bridge bots, lowercased.
    ///
    /// A bridge bot sits in every bridged room, so the server often picks it
    /// as a hero. It is not a person in the chat, and its face in the cluster
    /// would push out a real member. Each name is a default puppet prefix from
    /// `ChatListNetwork.localpartPrefixes` with "bot" in place of the
    /// underscore: `whatsapp_` gives `whatsappbot`, `meta_` gives `metabot`.
    public static let bridgeBotLocalparts: Set<String> = Set(
        ChatListNetwork.localpartPrefixes.map { (entry: (prefix: String, network: ChatListNetwork)) -> String in
            String(entry.prefix.dropLast()) + "bot"
        }
    )

    /// The heroes the avatar may show: the server's heroes without service
    /// members and bridge bots, in the server's order.
    ///
    /// - Parameters:
    ///   - heroes: the room's heroes, in the order the server sent them.
    ///   - serviceMembers: the user IDs the room's `io.element.functional_members`
    ///     state names as services (the SDK's `RoomInfo.serviceMembers`).
    /// - Returns: the heroes left after both filters. The order is unchanged.
    ///
    /// ```swift
    /// ChatListHero.visible(
    ///     [ChatListHero(userId: "@whatsappbot:example.org"), ChatListHero(userId: "@whatsapp_123:example.org")],
    ///     serviceMembers: []
    /// ) // [@whatsapp_123:example.org]
    /// ```
    public static func visible(_ heroes: [ChatListHero], serviceMembers: some Sequence<String>) -> [ChatListHero] {
        let services = Set(serviceMembers)
        return heroes.filter { hero in
            !services.contains(hero.userId) && !isBridgeBot(userId: hero.userId)
        }
    }

    /// True when the user ID's localpart is a default mautrix bridge bot name.
    /// The match ignores case and the server name.
    public static func isBridgeBot(userId: String) -> Bool {
        bridgeBotLocalparts.contains(ChatListSender.localpart(of: userId).lowercased())
    }
}
