import Foundation

/// When the iOS app stops and starts its sync, from the phases of its scenes
/// (MATRIX-242).
///
/// iOS can end a suspended app that holds a file lock in an App Group
/// container (`0xdead10cc`), and the SDK store is in the App Group container
/// (MATRIX-88). So the app stops sync before iOS suspends it, and starts it
/// again when the app returns to the foreground.
///
/// Sync is per client, not per scene. On an iPad with several scenes, sync
/// stops only when every scene is in the background, and starts again when
/// the first scene becomes active. An inactive scene (Control Center, the app
/// switcher, a system alert) changes nothing.
public struct SceneSyncLifecycle: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case active
        case inactive
        case background
    }

    public enum Change: Equatable, Sendable {
        /// The scene entered a phase.
        case entered(Phase)
        /// iOS disconnected the scene.
        case disconnected
    }

    public enum Action: Equatable, Sendable {
        /// Every scene is in the background: stop sync before iOS suspends
        /// the app.
        case stopForBackground
        /// A scene became active after the stop: start sync again.
        case startForForeground
    }

    /// The phase of each scene that entered a phase, by scene identifier.
    private var phases: [String: Phase] = [:]

    /// Whether the app stopped sync for the background, and no scene became
    /// active after that.
    public private(set) var isStoppedForBackground = false

    public init() {}

    /// Whether the app can start sync now. A session that attaches while
    /// every scene is in the background starts sync when a scene becomes
    /// active.
    public var allowsSync: Bool {
        !isStoppedForBackground
    }

    /// Records a change of one scene, and returns what the app must do.
    ///
    /// - Parameter scene: the scene's identifier, for example its session's
    ///   persistent identifier.
    public mutating func scene(_ scene: String, did change: Change) -> Action? {
        switch change {
        case let .entered(phase):
            phases[scene] = phase
        case .disconnected:
            // A scene that never entered a phase changes nothing.
            guard phases.removeValue(forKey: scene) != nil else { return nil }
        }

        if isStoppedForBackground {
            guard phases.values.contains(.active) else { return nil }
            isStoppedForBackground = false
            return .startForForeground
        }
        guard phases.values.allSatisfy({ $0 == .background }) else { return nil }
        isStoppedForBackground = true
        return .stopForBackground
    }
}
