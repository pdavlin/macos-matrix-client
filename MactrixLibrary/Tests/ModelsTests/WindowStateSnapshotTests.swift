import Foundation
@testable import Models
import Testing

/// MATRIX-175: the kept state of a main window, its store in the app's
/// defaults, and the rule for which window starts from the saved state.
struct WindowStateSnapshotTests {
    private static let full = WindowStateSnapshot(
        chatSelection: .merged("merged-1"),
        inspectorVisible: true,
        sidebarSections: SidebarSectionCollapsibility(spaces: false),
        chatListFilter: .unread,
        railFilter: .space("!dev:a")
    )

    /// A store on a suite made for the test. The suite is removed after
    /// `body`.
    private func withStore(_ body: (WindowStateStore, UserDefaults) throws -> Void) throws {
        let suite = "WindowStateSnapshotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(WindowStateStore(defaults: defaults), defaults)
    }

    // MARK: - The JSON value

    @Test func jsonRoundTripKeepsEachField() throws {
        let json = try #require(Self.full.json)
        let decoded = try #require(WindowStateSnapshot(json: json))
        #expect(decoded == Self.full)
        #expect(decoded.chatSelection == .merged("merged-1"))
        #expect(decoded.railFilter == .space("!dev:a"))
        #expect(decoded.restoredChatListFilter == .unread)
        #expect(decoded.inspectorVisible)
        #expect(!decoded.sidebarSections.spaces)
    }

    @Test func roomAndLabelRoundTrip() throws {
        let snapshot = WindowStateSnapshot(chatSelection: .room("!room:a"), railFilter: .label("label-1"))
        let decoded = try #require(snapshot.json.flatMap(WindowStateSnapshot.init(json:)))
        #expect(decoded.chatSelection == .room("!room:a"))
        #expect(decoded.railFilter == .label("label-1"))
    }

    @Test func emptyStateRoundTrip() throws {
        let decoded = try #require(WindowStateSnapshot().json.flatMap(WindowStateSnapshot.init(json:)))
        #expect(decoded.chatSelection == nil)
        #expect(decoded.railFilter == .inbox)
        #expect(decoded.restoredChatListFilter == .inbox)
    }

    /// The keys are those of `WindowState.SceneStorageRepresentation`, the
    /// type before MATRIX-175: a value stored by an older build decodes.
    @Test func keysAreTheKeysOfTheOldRepresentation() throws {
        let json = try #require(Self.full.json)
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(Set(object.keys) == [
            "selectedMergedChatId", "inspectorVisible", "sidebarSections", "chatListFilter", "selectedSpaceId",
        ])
        #expect(object["selectedMergedChatId"] as? String == "merged-1")
        #expect(object["selectedSpaceId"] as? String == "!dev:a")
    }

    /// A value from before MATRIX-67, MATRIX-77, MATRIX-141 and MATRIX-167:
    /// no filter, no label, no merged chat, no space. The old sidebar
    /// section keys are ignored.
    @Test func decodesAValueWithoutTheNewerOptionalFields() throws {
        let old = """
        {"selectedRoomId":"!room:a","inspectorVisible":true,\
        "sidebarSections":{"spaces":false,"favorites":true,"directs":true,"rooms":false}}
        """
        let decoded = try #require(WindowStateSnapshot(json: old))
        #expect(decoded.chatSelection == .room("!room:a"))
        #expect(decoded.inspectorVisible)
        #expect(!decoded.sidebarSections.spaces)
        #expect(decoded.restoredChatListFilter == .inbox)
        #expect(decoded.railFilter == .inbox)
    }

    @Test func decodesAValueWithNoSelection() throws {
        let decoded = try #require(WindowStateSnapshot(json: #"{"inspectorVisible":false,"sidebarSections":{"spaces":true}}"#))
        #expect(decoded.chatSelection == nil)
    }

    /// A merged chat wins over a room, and a space over a label, as before
    /// MATRIX-175.
    @Test func mergedChatAndSpaceWin() throws {
        let both = """
        {"selectedRoomId":"!room:a","selectedMergedChatId":"merged-1","inspectorVisible":false,\
        "sidebarSections":{"spaces":true},"selectedLabelId":"label-1","selectedSpaceId":"!dev:a"}
        """
        let decoded = try #require(WindowStateSnapshot(json: both))
        #expect(decoded.chatSelection == .merged("merged-1"))
        #expect(decoded.railFilter == .space("!dev:a"))
    }

    @Test func aValueThatIsNotTheFormatGivesNil() {
        #expect(WindowStateSnapshot(json: "") == nil)
        #expect(WindowStateSnapshot(json: "not json") == nil)
        #expect(WindowStateSnapshot(json: #"{"selectedRoomId":"!room:a"}"#) == nil)
    }

    /// The snapshot keeps a space that the rail does not show yet. The
    /// filter shows the Inbox until the space arrives, and the saved
    /// selection is not cleared.
    @Test func aSpaceThatIsNotKnownYetStaysInTheSnapshot() throws {
        let restored = try #require(Self.full.json.flatMap(WindowStateSnapshot.init(json:))).railFilter
        #expect(restored.resolved(labels: ChatLabelDocument(), spaceIds: []) == .inbox)
        #expect(restored.resolved(labels: ChatLabelDocument(), spaceIds: ["!dev:a"]) == .space("!dev:a"))
        #expect(restored == .space("!dev:a"))
    }

    // MARK: - The store

    @Test func storeHasNoStateAtFirst() throws {
        try withStore { store, _ in
            #expect(store.load() == nil)
        }
    }

    @Test func storeSaveAndLoadRoundTrip() throws {
        try withStore { store, defaults in
            store.save(Self.full)
            #expect(store.load() == Self.full)
            // A second store on the same defaults, as a new launch has.
            #expect(WindowStateStore(defaults: defaults).load() == Self.full)
        }
    }

    @Test func theLastStateWrittenIsTheStoredState() throws {
        try withStore { store, _ in
            store.save(Self.full)
            let second = WindowStateSnapshot(chatSelection: .room("!other:a"))
            store.save(second)
            #expect(store.load() == second)
        }
    }

    /// A cleared selection is a state too: it replaces the stored chat.
    @Test func aClearedSelectionIsStored() throws {
        try withStore { store, _ in
            store.save(Self.full)
            store.save(WindowStateSnapshot())
            #expect(store.load() == WindowStateSnapshot())
        }
    }

    @Test func theStoredValueIsOneJSONString() throws {
        try withStore { store, defaults in
            store.save(Self.full)
            #expect(defaults.string(forKey: WindowStateStore.storageKey) == Self.full.json)
        }
    }

    @Test func storeReadsAValueOfAnOlderBuild() throws {
        try withStore { store, defaults in
            defaults.set(
                #"{"selectedRoomId":"!room:a","inspectorVisible":false,"sidebarSections":{"spaces":true}}"#,
                forKey: WindowStateStore.storageKey
            )
            #expect(store.load()?.chatSelection == .room("!room:a"))
        }
    }

    @Test func aStoredValueThatDoesNotDecodeLoadsAsNoState() throws {
        try withStore { store, defaults in
            defaults.set("not json", forKey: WindowStateStore.storageKey)
            #expect(store.load() == nil)
            // The next save replaces it.
            store.save(Self.full)
            #expect(store.load() == Self.full)
        }
    }

    // MARK: - Which window restores

    @Test func theFirstWindowOfALaunchStartsFromTheSavedState() {
        var rule = LaunchWindowRestore()
        #expect(rule.source(hasSceneStorageValue: false) == .savedState)
    }

    /// File > New Window in a running app: no copy of the first window's
    /// selection.
    @Test func aLaterNewWindowStartsEmpty() {
        var rule = LaunchWindowRestore()
        _ = rule.source(hasSceneStorageValue: false)
        #expect(rule.source(hasSceneStorageValue: false) == .none)
        #expect(rule.source(hasSceneStorageValue: false) == .none)
    }

    @Test func aWindowThatMacOSRestoredKeepsItsOwnState() {
        var rule = LaunchWindowRestore()
        #expect(rule.source(hasSceneStorageValue: true) == .sceneStorage)
        #expect(rule.source(hasSceneStorageValue: true) == .sceneStorage)
    }

    /// The first window uses up the one restore of the launch, also when
    /// macOS restored it.
    @Test func aNewWindowAfterARestoredWindowStartsEmpty() {
        var rule = LaunchWindowRestore()
        _ = rule.source(hasSceneStorageValue: true)
        #expect(rule.source(hasSceneStorageValue: false) == .none)
    }

    @Test func eachLaunchHasItsOwnRule() {
        var first = LaunchWindowRestore()
        _ = first.source(hasSceneStorageValue: false)
        var second = LaunchWindowRestore()
        #expect(second.source(hasSceneStorageValue: false) == .savedState)
    }
}
