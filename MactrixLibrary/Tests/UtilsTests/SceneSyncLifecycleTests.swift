import Testing
import Utils

/// MATRIX-242: the iOS app stops sync when every scene is in the background,
/// and starts it again when the first scene becomes active.
struct SceneSyncLifecycleTests {
    /// Applies the changes in order, and returns the action of each one.
    private static func actions(
        _ changes: [(String, SceneSyncLifecycle.Change)],
        on lifecycle: inout SceneSyncLifecycle
    ) -> [SceneSyncLifecycle.Action?] {
        changes.map { lifecycle.scene($0.0, did: $0.1) }
    }

    /// A launch: the scene enters the foreground and becomes active.
    private static let launch: [(String, SceneSyncLifecycle.Change)] = [
        ("a", .entered(.inactive)),
        ("a", .entered(.active)),
    ]

    // MARK: One scene

    @Test func aNewLifecycleAllowsSync() {
        let lifecycle = SceneSyncLifecycle()
        #expect(lifecycle.allowsSync)
        #expect(!lifecycle.isStoppedForBackground)
    }

    @Test func aLaunchToTheForegroundDoesNothing() {
        var lifecycle = SceneSyncLifecycle()
        #expect(Self.actions(Self.launch, on: &lifecycle) == [nil, nil])
        #expect(lifecycle.allowsSync)
    }

    @Test func theBackgroundStopsSync() {
        var lifecycle = SceneSyncLifecycle()
        _ = Self.actions(Self.launch, on: &lifecycle)

        let actions = Self.actions([("a", .entered(.inactive)), ("a", .entered(.background))], on: &lifecycle)

        #expect(actions == [nil, .stopForBackground])
        #expect(!lifecycle.allowsSync)
    }

    /// Control Center, the app switcher, or a system alert.
    @Test func anInactiveSceneKeepsSync() {
        var lifecycle = SceneSyncLifecycle()
        _ = Self.actions(Self.launch, on: &lifecycle)

        let actions = Self.actions([("a", .entered(.inactive)), ("a", .entered(.active))], on: &lifecycle)

        #expect(actions == [nil, nil])
        #expect(lifecycle.allowsSync)
    }

    @Test func theForegroundStartsSyncWhenTheSceneBecomesActive() {
        var lifecycle = SceneSyncLifecycle()
        _ = Self.actions(Self.launch + [("a", .entered(.background))], on: &lifecycle)

        let actions = Self.actions([("a", .entered(.inactive)), ("a", .entered(.active))], on: &lifecycle)

        #expect(actions == [nil, .startForForeground])
        #expect(lifecycle.allowsSync)
    }

    @Test func eachStopAndStartOccursOneTime() {
        var lifecycle = SceneSyncLifecycle()
        _ = Self.actions(Self.launch, on: &lifecycle)

        let actions = Self.actions(
            [
                ("a", .entered(.background)),
                ("a", .entered(.background)),
                ("a", .entered(.active)),
                ("a", .entered(.active)),
            ],
            on: &lifecycle
        )

        #expect(actions == [.stopForBackground, nil, .startForForeground, nil])
    }

    /// A session that attaches now waits for the foreground to start sync.
    @Test func aLaunchInTheBackgroundStopsSync() {
        var lifecycle = SceneSyncLifecycle()

        #expect(lifecycle.scene("a", did: .entered(.background)) == .stopForBackground)
        #expect(!lifecycle.allowsSync)
        #expect(lifecycle.scene("a", did: .entered(.active)) == .startForForeground)
    }

    // MARK: Several scenes

    @Test func syncStopsOnlyWhenEverySceneIsInTheBackground() {
        var lifecycle = SceneSyncLifecycle()

        let actions = Self.actions(
            [
                ("a", .entered(.active)),
                ("b", .entered(.active)),
                ("a", .entered(.background)),
                ("b", .entered(.inactive)),
                ("b", .entered(.background)),
            ],
            on: &lifecycle
        )

        #expect(actions == [nil, nil, nil, nil, .stopForBackground])
    }

    @Test func theFirstActiveSceneStartsSync() {
        var lifecycle = SceneSyncLifecycle()
        _ = Self.actions(
            [
                ("a", .entered(.active)),
                ("b", .entered(.active)),
                ("a", .entered(.background)),
                ("b", .entered(.background)),
            ],
            on: &lifecycle
        )

        let actions = Self.actions(
            [
                ("b", .entered(.inactive)),
                ("b", .entered(.active)),
                ("a", .entered(.active)),
            ],
            on: &lifecycle
        )

        #expect(actions == [nil, .startForForeground, nil])
    }

    @Test func aNewSceneThatBecomesActiveStartsSync() {
        var lifecycle = SceneSyncLifecycle()
        _ = Self.actions(Self.launch + [("a", .entered(.background))], on: &lifecycle)

        #expect(lifecycle.scene("b", did: .entered(.active)) == .startForForeground)
    }

    /// The last scene in the foreground closes: only background scenes stay.
    @Test func aDisconnectedSceneNoLongerKeepsSync() {
        var lifecycle = SceneSyncLifecycle()
        _ = Self.actions([("a", .entered(.background)), ("b", .entered(.active))], on: &lifecycle)
        #expect(lifecycle.allowsSync)

        #expect(lifecycle.scene("b", did: .disconnected) == .stopForBackground)
    }

    @Test func aBackgroundSceneThatDisconnectsKeepsSync() {
        var lifecycle = SceneSyncLifecycle()
        _ = Self.actions([("a", .entered(.active)), ("b", .entered(.background))], on: &lifecycle)

        #expect(lifecycle.scene("b", did: .disconnected) == nil)
        #expect(lifecycle.allowsSync)
    }

    @Test func anUnknownSceneThatDisconnectsChangesNothing() {
        var lifecycle = SceneSyncLifecycle()

        #expect(lifecycle.scene("a", did: .disconnected) == nil)
        #expect(lifecycle.allowsSync)
    }
}
