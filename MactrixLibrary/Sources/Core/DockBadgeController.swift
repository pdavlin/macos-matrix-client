#if os(macOS)
    import AppKit
#endif
import Foundation
import MatrixRustSDK
import Models
import Observation

/// Keeps the Dock icon's badge equal to the number of unread chats
/// (MATRIX-119).
///
/// `MatrixClient` owns one for the client's life: `startSync()` calls
/// `start(roomListService:labels:)`, and `reset()` (sign-out) calls `stop()`.
/// On iOS both are no-ops, so the shared code compiles and no room list runs
/// for a Dock that does not exist.
///
/// The count is read inside Observation tracking: when the tracker publishes
/// or the labels change, the badge is computed again. The Settings switch
/// lives in `UserDefaults`, which Observation does not see, so the controller
/// also listens for `UserDefaults.didChangeNotification`; turning the switch
/// off clears the badge at once.
///
/// The counting rule is not here: see `DockBadge`.
@MainActor
public final class DockBadgeController {
    /// The unread state of every non-space room.
    public let unreadChats = UnreadChatsTracker()

    private let settingsStore: UserDefaults
    /// Weak: `MatrixClient` owns the labels model.
    private weak var labels: LabelsModel?

    private var isRunning = false
    /// Increases with each `stop()`. A `start` that was waiting for the room
    /// list when sign-out stopped the controller does not turn it back on.
    private var stopCount = 0
    /// Increases with each tracking pass. A change callback from an older
    /// pass is ignored, so a refresh from the defaults listener does not
    /// leave a second live tracking pass behind.
    private var trackingGeneration = 0
    /// The label last written to the Dock tile. `.none` before the first
    /// write; `.some(nil)` means "no badge".
    private var appliedLabel: String??
    private var defaultsObserver: (any NSObjectProtocol)?

    /// MATRIX-144: the account's merged chats. A merged chat counts once,
    /// however many members are unread
    /// (`DockBadge.unreadChatCount(_:labelMutedRoomIds:mergedChats:)`).
    /// Defaults to no merges, which counts as before MATRIX-144; the M2.5
    /// integration story sets it to the merged-chats model's document.
    ///
    /// Read inside Observation tracking, so a closure that reads an
    /// `@Observable` property recomputes the badge when it changes. Setting
    /// it recomputes the badge at once.
    public var mergedChats: @MainActor () -> MergedChatDocument = { MergedChatDocument() } {
        didSet { refresh() }
    }

    /// - Parameter settingsStore: the defaults store that Settings >
    ///   Notifications writes with `@AppStorage`.
    public init(settingsStore: UserDefaults = .standard) {
        self.settingsStore = settingsStore
    }

    /// The number of chats with unread activity, by the rule in `DockBadge`.
    /// Observable through `unreadChats`, the labels, and `mergedChats`.
    public var unreadChatCount: Int {
        DockBadge.unreadChatCount(
            unreadChats.chats.values,
            labelMutedRoomIds: labels?.document.labelMutedRoomIds ?? [],
            mergedChats: mergedChats()
        )
    }

    /// Opens the room list and shows the badge. A second call (Restart sync
    /// builds a new room list service) restarts the room list on the new
    /// service. Does nothing on iOS.
    ///
    /// - Parameters:
    ///   - roomListService: the room list service `startSync()` just built.
    ///   - labels: the account's labels, for the MATRIX-77 label mute.
    public func start(roomListService: RoomListService, labels: LabelsModel?) async {
        #if os(macOS)
            let stopCountAtStart = stopCount
            self.labels = labels
            unreadChats.stop()
            await unreadChats.start(roomListService: roomListService)
            guard stopCount == stopCountAtStart else {
                unreadChats.stop()
                return
            }
            if !isRunning {
                isRunning = true
                defaultsObserver = NotificationCenter.default.addObserver(
                    forName: UserDefaults.didChangeNotification,
                    object: settingsStore,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.refresh()
                    }
                }
            }
            refresh()
        #endif
    }

    /// Closes the room list and removes the badge.
    public func stop() {
        stopCount += 1
        unreadChats.stop()
        labels = nil
        guard isRunning else { return }
        isRunning = false
        trackingGeneration += 1
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        defaultsObserver = nil
        apply(nil)
    }

    private func refresh() {
        guard isRunning else { return }
        trackingGeneration += 1
        let generation = trackingGeneration
        let label: String? = withObservationTracking {
            DockBadge.label(
                unreadChatCount: unreadChatCount,
                isEnabled: NotificationPreferences(defaults: settingsStore).showsDockBadge
            )
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.trackingGeneration else { return }
                self.refresh()
            }
        }
        apply(label)
    }

    /// Writes `label` to the Dock tile if it differs from the last write.
    private func apply(_ label: String?) {
        if case let .some(applied) = appliedLabel, applied == label {
            return
        }
        appliedLabel = .some(label)
        #if os(macOS)
            NSApp.dockTile.badgeLabel = label
        #endif
    }
}
