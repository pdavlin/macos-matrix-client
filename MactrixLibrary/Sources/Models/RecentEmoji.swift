import Foundation
import Observation

/// One emoji from the account's recent-emoji list (MATRIX-111, M2-B4, D-3).
///
/// The SDK stores the list in account data, so it syncs with Element X and
/// the other clients of the account. `Core` builds these from the SDK's
/// `RecentEmoji` records.
public struct RecentEmojiEntry: Hashable, Sendable {
    public let emoji: String
    /// How often the account used the emoji. The app does not show it.
    public let count: UInt64

    public init(emoji: String, count: UInt64) {
        self.emoji = emoji
        self.count = count
    }
}

/// The rules for the local copy of the recent-emoji list.
public enum RecentEmojiList {
    /// The list after one use of `emoji`.
    ///
    /// The emoji moves to the front and its count goes up by one; a new emoji
    /// goes to the front with a count of one. This mirrors what the SDK's
    /// `addRecentEmoji` writes, so the local copy shows the same order as the
    /// next read from the SDK.
    ///
    /// - Parameters:
    ///   - emoji: The emoji that was used.
    ///   - entries: The list, most recent first.
    /// - Returns: The new list, most recent first.
    public static func recording(_ emoji: String, in entries: [RecentEmojiEntry]) -> [RecentEmojiEntry] {
        var remaining = entries
        var count: UInt64 = 1
        if let index = remaining.firstIndex(where: { $0.emoji == emoji }) {
            count = remaining[index].count + 1
            remaining.remove(at: index)
        }
        return [RecentEmojiEntry(emoji: emoji, count: count)] + remaining
    }

    /// The list a load from the SDK gives, with the uses since the session
    /// started applied on top.
    ///
    /// A use can happen before the first load returns, and the SDK may not
    /// have written it yet when it answers the read. Applying the uses again
    /// keeps them at the front. A use the SDK already has moves to the front
    /// again, which leaves the order unchanged; only its count can be one too
    /// high, and the app does not show counts.
    ///
    /// - Parameters:
    ///   - loaded: The SDK's list, most recent first.
    ///   - uses: The emoji used in this session before the load, oldest first.
    /// - Returns: The merged list, most recent first.
    public static func merging(loaded: [RecentEmojiEntry], uses: [String]) -> [RecentEmojiEntry] {
        uses.reduce(loaded) { entries, emoji in recording(emoji, in: entries) }
    }
}

/// The session's recent-emoji list (MATRIX-111).
///
/// The app reads the SDK list once per session (`loadIfNeeded(_:)`) and then
/// keeps it up to date locally after each reaction (`record(_:)`), so a hover
/// over a message never calls the SDK. The hover row's quick reactions and
/// the picker's top row both read `emojis`.
///
/// Usage (in `Core`):
/// ```swift
/// try await store.loadIfNeeded { try await sdkRecents() }
/// store.record("🎉")
/// ```
@MainActor @Observable
public final class RecentEmojiStore {
    /// The recent emoji, most recent first.
    public private(set) var entries: [RecentEmojiEntry] = []

    private enum Phase {
        case notLoaded
        case loading
        case loaded
    }

    @ObservationIgnored private var phase: Phase = .notLoaded
    /// Uses recorded before a load succeeded, oldest first.
    @ObservationIgnored private var usesBeforeLoad: [String] = []

    public init() {}

    /// The recent emoji strings, most recent first.
    public var emojis: [String] {
        entries.map(\.emoji)
    }

    /// The hover row's quick reactions for this list.
    public var quickReactionKeys: [String] {
        MessageActionModel.quickReactionKeys(fromRecents: emojis)
    }

    /// Whether a load succeeded in this session.
    public var hasLoaded: Bool {
        phase == .loaded
    }

    /// Loads the list once. Calls while a load runs, or after one succeeded,
    /// return at once. After a failure the next call tries again.
    ///
    /// - Parameter fetch: Reads the list from the SDK, most recent first.
    /// - Throws: The error of `fetch`.
    public func loadIfNeeded(_ fetch: @MainActor () async throws -> [RecentEmojiEntry]) async throws {
        guard phase == .notLoaded else { return }
        phase = .loading
        do {
            let loaded = try await fetch()
            entries = RecentEmojiList.merging(loaded: loaded, uses: usesBeforeLoad)
            usesBeforeLoad = []
            phase = .loaded
        } catch {
            phase = .notLoaded
            throw error
        }
    }

    /// Records one use of `emoji` in the local list. The caller also sends
    /// the use to the SDK.
    public func record(_ emoji: String) {
        entries = RecentEmojiList.recording(emoji, in: entries)
        if phase != .loaded {
            usesBeforeLoad.append(emoji)
        }
    }
}
