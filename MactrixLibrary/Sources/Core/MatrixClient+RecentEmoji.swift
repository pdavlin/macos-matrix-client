import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The SDK side of the account's recent emoji (MATRIX-111, M2-B4, D-3).
///
/// The SDK keeps the list in account data, so it is the same list Element X
/// shows. The app reads it once per session and then updates its local copy
/// after each reaction, so a hover over a message never calls the SDK. The
/// list rules live in `Models.RecentEmojiList`, where they are unit-tested.
public extension MatrixClient {
    /// Reads the recent emoji from the SDK, once per session. Later calls
    /// return at once; after a failed read the next call tries again.
    func loadRecentEmojisIfNeeded() async {
        guard let sdkClient: ClientProtocol = client else { return }
        do {
            try await recentEmojis.loadIfNeeded {
                let recents: [MatrixRustSDK.RecentEmoji] = try await sdkClient.getRecentEmojis()
                return recents.map { RecentEmojiEntry(emoji: $0.emoji, count: $0.count) }
            }
        } catch {
            Logger.matrixClient.error("failed to read recent emoji: \(String(describing: error), privacy: .public)")
        }
    }

    /// Records one use of `emoji`: the local list updates at once, and the
    /// SDK adds the use to the account's list in the background.
    ///
    /// A custom emoji (an `mxc://` key, MATRIX-155) is not recorded, on any
    /// path: the rule is `RecentEmojiList.isRecordable(_:)`, and the store
    /// answers false for such a key.
    func recordRecentEmoji(_ emoji: String) {
        guard recentEmojis.record(emoji) else { return }
        guard let sdkClient: ClientProtocol = client else { return }
        Task {
            do {
                try await sdkClient.addRecentEmoji(emoji: emoji)
            } catch {
                Logger.matrixClient.error("failed to add recent emoji: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
