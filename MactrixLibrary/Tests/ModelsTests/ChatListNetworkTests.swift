@testable import Models
import Testing

/// MATRIX-67: the bridge-network display heuristic.
struct ChatListNetworkTests {
    @Test(arguments: [
        ("@slack_U123:example.org", ChatListNetwork.slack),
        ("@whatsapp_15551234567:example.org", .whatsApp),
        ("@signal_abc:example.org", .signal),
        ("@discord_42:example.org", .discord),
        ("@telegram_42:example.org", .telegram),
        ("@googlechat_42:example.org", .googleChat),
        ("@groupme_42:example.org", .groupMe),
        ("@meta_42:example.org", .meta),
        ("@instagram_42:example.org", .instagram),
        ("@facebook_42:example.org", .facebook),
        ("@gmessages_42:example.org", .googleMessages),
        ("@linkedin_42:example.org", .linkedIn),
        ("@twitter_42:example.org", .twitter),
    ])
    func detectsEachDefaultPrefix(userId: String, network: ChatListNetwork) {
        #expect(ChatListNetwork.detect(heroUserIds: [userId]) == network)
    }

    @Test
    func everyNetworkHasAPrefix() {
        let covered = Set(ChatListNetwork.localpartPrefixes.map(\.network))
        #expect(covered == Set(ChatListNetwork.allCases))
    }

    @Test
    func returnsNilWhenNoHeroMatches() {
        #expect(ChatListNetwork.detect(heroUserIds: ["@alice:example.org", "@bob:example.org"]) == nil)
        #expect(ChatListNetwork.detect(heroUserIds: []) == nil)
    }

    @Test
    func firstMatchingHeroWins() {
        let heroes = ["@alice:example.org", "@signal_1:example.org", "@whatsapp_2:example.org"]
        #expect(ChatListNetwork.detect(heroUserIds: heroes) == .signal)
    }

    /// The prefix must start the localpart; the server name is never matched.
    @Test
    func matchesTheLocalpartOnly() {
        #expect(ChatListNetwork.detect(heroUserIds: ["@alice:slack_bridge.example.org"]) == nil)
        #expect(ChatListNetwork.detect(heroUserIds: ["@my_signal_1:example.org"]) == nil)
    }

    @Test
    func matchIgnoresCase() {
        #expect(ChatListNetwork.detect(heroUserIds: ["@WhatsApp_1:example.org"]) == .whatsApp)
    }
}
