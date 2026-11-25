import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The quick reactions of a room (MATRIX-262), and the uses that rank them.
///
/// The rule lives in `Models.QuickReactionRanking`, and the store and its
/// write gate in `Models.ReactionUsageStore`, where they are unit-tested.
/// This file feeds them from the client: the reaction use in account data,
/// the rail's space map, the labels, and the recent emoji.
public extension MatrixClient {
    /// The hover row's and the React submenus' quick reactions for a
    /// message in `roomId`. In a merged chat, `roomId` is the member room
    /// that holds the message.
    func quickReactionKeys(forRoom roomId: String) -> [String] {
        QuickReactionRanking.keys(
            forRoom: roomId,
            usage: reactionUsage?.document ?? ReactionUsageDocument(),
            spaces: roomAccounts.spaceMap,
            labels: labels?.document ?? ChatLabelDocument(),
            recents: recentEmojis.emojis
        )
    }

    /// Records the outcome of a reaction toggle in `roomId`. An added
    /// reaction is a use of `key` in the room and in the account's recent
    /// list (D-3). A removed reaction is not a use.
    func recordReactionToggle(_ key: String, inRoom roomId: String, wasAdded: Bool) {
        reactionUsage?.recordToggle(of: key, inRoom: roomId, wasAdded: wasAdded)
        if wasAdded {
            recordRecentEmoji(key)
        }
    }

    /// Records an emoji picked in the composer (MATRIX-234) as a use in
    /// `roomId`, the room the message goes to, and in the account's recent
    /// list.
    func recordComposerEmojiPick(_ key: String, inRoom roomId: String) {
        reactionUsage?.record(key, inRoom: roomId)
        recordRecentEmoji(key)
    }

    /// The store, with the SDK's account data calls as its transport, as
    /// the labels use them.
    internal func makeReactionUsageStore() -> ReactionUsageStore {
        let sdkClient: ClientProtocol = client
        return ReactionUsageStore(transport: ReactionUsageStore.Transport(
            read: { try await sdkClient.accountData(eventType: ReactionUsageDocument.eventType) },
            write: { content in try await sdkClient.setAccountData(eventType: ReactionUsageDocument.eventType, content: content) },
            report: { line in Logger.matrixClient.error("\(line, privacy: .public)") }
        ))
    }
}
