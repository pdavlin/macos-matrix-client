import Models
import Testing

/// MATRIX-111 (M2-B4): the local copy of the account's recent emoji.
struct RecentEmojiListTests {
    private func entries(_ pairs: [(String, UInt64)]) -> [RecentEmojiEntry] {
        pairs.map { RecentEmojiEntry(emoji: $0.0, count: $0.1) }
    }

    @Test func aNewEmojiGoesToTheFrontWithACountOfOne() {
        let list = RecentEmojiList.recording("🔥", in: entries([("😂", 4), ("👀", 2)]))
        #expect(list == entries([("🔥", 1), ("😂", 4), ("👀", 2)]))
    }

    @Test func aKnownEmojiMovesToTheFrontAndCountsUp() {
        let list = RecentEmojiList.recording("👀", in: entries([("😂", 4), ("👀", 2), ("🙏", 1)]))
        #expect(list == entries([("👀", 3), ("😂", 4), ("🙏", 1)]))
    }

    @Test func mergeAppliesSessionUsesOnTopOfTheLoadedList() {
        let loaded = entries([("😂", 4), ("👀", 2)])
        let merged = RecentEmojiList.merging(loaded: loaded, uses: ["🔥", "👀"])
        #expect(merged.map(\.emoji) == ["👀", "🔥", "😂"])
    }

    @Test func mergeWithoutUsesKeepsTheLoadedList() {
        let loaded = entries([("😂", 4), ("👀", 2)])
        #expect(RecentEmojiList.merging(loaded: loaded, uses: []) == loaded)
    }
}

/// MATRIX-111: the session store reads the SDK once and then updates locally.
@MainActor
struct RecentEmojiStoreTests {
    private struct ReadFailed: Error {}

    @Test func startsEmptyWithTheDefaultQuickReactions() {
        let store = RecentEmojiStore()
        #expect(store.emojis.isEmpty)
        #expect(store.quickReactionKeys == MessageActionModel.defaultQuickReactionKeys)
    }

    @Test func loadsOnceAndThenSkipsTheSDK() async throws {
        let store = RecentEmojiStore()
        var reads = 0
        try await store.loadIfNeeded {
            reads += 1
            return [RecentEmojiEntry(emoji: "😂", count: 3), RecentEmojiEntry(emoji: "🔥", count: 1)]
        }
        try await store.loadIfNeeded {
            reads += 1
            return []
        }
        #expect(reads == 1)
        #expect(store.hasLoaded)
        #expect(store.emojis == ["😂", "🔥"])
        #expect(store.quickReactionKeys == ["😂", "🔥", "👍"])
    }

    @Test func aFailedLoadTriesAgainNextTime() async throws {
        let store = RecentEmojiStore()
        await #expect(throws: ReadFailed.self) {
            try await store.loadIfNeeded { throw ReadFailed() }
        }
        #expect(!store.hasLoaded)
        try await store.loadIfNeeded { [RecentEmojiEntry(emoji: "🙏", count: 1)] }
        #expect(store.emojis == ["🙏"])
    }

    @Test func aUseBeforeTheLoadStaysAtTheFront() async throws {
        let store = RecentEmojiStore()
        store.record("🎉")
        #expect(store.emojis == ["🎉"])
        try await store.loadIfNeeded { [RecentEmojiEntry(emoji: "😂", count: 3)] }
        #expect(store.emojis == ["🎉", "😂"])
    }

    @Test func aUseAfterTheLoadUpdatesTheQuickReactions() async throws {
        let store = RecentEmojiStore()
        try await store.loadIfNeeded {
            ["😂", "🔥", "👀"].map { RecentEmojiEntry(emoji: $0, count: 1) }
        }
        store.record("🙏")
        #expect(store.quickReactionKeys == ["🙏", "😂", "🔥"])
        store.record("👀")
        #expect(store.quickReactionKeys == ["👀", "🙏", "😂"])
    }
}
