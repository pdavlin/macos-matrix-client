import Foundation

/// The chat network a bridged room most likely belongs to (MATRIX-67).
///
/// This is a display heuristic, not a fact about the room. A mautrix bridge
/// announces itself in the room's `m.bridge` state event, but the FFI's state
/// read (`Room.stateEvents`) holds only the state that the sliding sync asks
/// for, and `m.bridge` is not part of it (MATRIX-219), so the row cannot read
/// it. Instead the
/// detector matches the localparts of the room's heroes against the default
/// mautrix puppet prefixes (`whatsapp_…`, `signal_…`). A bridge configured with
/// a custom username template is not detected, and a native Matrix user whose
/// localpart happens to start with a prefix is misdetected. The result picks
/// a badge, and the reply style of the room (MATRIX-232,
/// `ThreadedReplyRule`): a Slack room puts every reply in a thread. Nothing
/// groups on it (contract D-4 still defers bridge-network grouping).
public enum ChatListNetwork: String, CaseIterable, Sendable {
    case slack
    case whatsApp
    case signal
    case discord
    case telegram
    case googleChat
    case groupMe
    case meta
    case instagram
    case facebook
    case googleMessages
    case linkedIn
    case twitter

    /// The user-facing network name, for VoiceOver and tooltips.
    public var displayName: String {
        switch self {
        case .slack: "Slack"
        case .whatsApp: "WhatsApp"
        case .signal: "Signal"
        case .discord: "Discord"
        case .telegram: "Telegram"
        case .googleChat: "Google Chat"
        case .groupMe: "GroupMe"
        case .meta: "Meta"
        case .instagram: "Instagram"
        case .facebook: "Messenger"
        case .googleMessages: "Google Messages"
        case .linkedIn: "LinkedIn"
        case .twitter: "X"
        }
    }

    /// The SF Symbol of the avatar badge (MATRIX-194): a letter in a filled
    /// circle, drawn with palette rendering in the network's tint.
    ///
    /// Deliberately not a brand logo. Networks that share a letter (Slack
    /// and Signal) differ by tint. A custom symbol template can replace a
    /// default here later; the badge view reads the name from this property
    /// only.
    public var badgeSymbolName: String {
        switch self {
        case .slack: "s.circle.fill"
        case .whatsApp: "w.circle.fill"
        case .signal: "s.circle.fill"
        case .discord: "d.circle.fill"
        case .telegram: "t.circle.fill"
        case .googleChat: "g.circle.fill"
        case .groupMe: "g.circle.fill"
        case .meta: "m.circle.fill"
        case .instagram: "i.circle.fill"
        case .facebook: "f.circle.fill"
        case .googleMessages: "m.circle.fill"
        case .linkedIn: "l.circle.fill"
        case .twitter: "x.circle.fill"
        }
    }

    /// Default mautrix puppet localpart prefixes, in match order.
    ///
    /// `meta_` is the mautrix-meta default for both Instagram and Messenger;
    /// `instagram_` and `facebook_` are the older per-network defaults.
    public static let localpartPrefixes: [(prefix: String, network: ChatListNetwork)] = [
        ("slack_", .slack),
        ("whatsapp_", .whatsApp),
        ("signal_", .signal),
        ("discord_", .discord),
        ("telegram_", .telegram),
        ("googlechat_", .googleChat),
        ("groupme_", .groupMe),
        ("meta_", .meta),
        ("instagram_", .instagram),
        ("facebook_", .facebook),
        ("gmessages_", .googleMessages),
        ("linkedin_", .linkedIn),
        ("twitter_", .twitter),
    ]

    /// The network of the first user whose localpart carries a known puppet
    /// prefix (`slack_…`) or is a default mautrix bridge bot (`slackbot`), or
    /// nil when no user matches.
    ///
    /// The bridge bot matters for a room with a name (MATRIX-147): the
    /// server sends no puppet as a hero there, but the bot is a hero or a
    /// service member.
    public static func detect(heroUserIds: some Sequence<String>) -> ChatListNetwork? {
        for userId in heroUserIds {
            let localpart = ChatListSender.localpart(of: userId).lowercased()
            if let match = localpartPrefixes.first(where: { localpart.hasPrefix($0.prefix) || localpart == $0.prefix.dropLast() + "bot" }) {
                return match.network
            }
        }
        return nil
    }
}

/// The switch for the avatar network badges in the sidebar (MATRIX-194,
/// Settings > Appearance).
///
/// Stored with `@AppStorage` under `storageKey`. The key is a persisted user
/// setting: do not rename it. A key that was never written reads as the
/// default, on.
public enum NetworkBadgePreferences {
    /// `UserDefaults` key of the switch.
    public static let storageKey = "showsNetworkBadges"
    /// The value when the user never changed it.
    public static let defaultValue = true

    /// The stored value, or the default.
    public static func isOn(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}
