import Foundation

/// The chat network a bridged room most likely belongs to (MATRIX-67).
///
/// This is a display heuristic, not a fact about the room. A mautrix bridge
/// announces itself in the room's `m.bridge` state event, but the FFI has no
/// API to read arbitrary room state, so the row cannot read it. Instead the
/// detector matches the localparts of the room's heroes against the default
/// mautrix puppet prefixes (`whatsapp_…`, `signal_…`). A bridge configured with
/// a custom username template is not detected, and a native Matrix user whose
/// localpart happens to start with a prefix is misdetected. The result only
/// picks a badge; nothing groups or routes on it (contract D-4 still defers
/// bridge-network grouping).
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

    /// The network of the first hero whose localpart carries a known puppet
    /// prefix, or nil when no hero matches.
    public static func detect(heroUserIds: some Sequence<String>) -> ChatListNetwork? {
        for userId in heroUserIds {
            let localpart = ChatListSender.localpart(of: userId).lowercased()
            if let match = localpartPrefixes.first(where: { localpart.hasPrefix($0.prefix) }) {
                return match.network
            }
        }
        return nil
    }
}
