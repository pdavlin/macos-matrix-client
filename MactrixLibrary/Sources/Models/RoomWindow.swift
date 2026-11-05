import Foundation

/// The value a single-room window is keyed by (MATRIX-116, D-8).
///
/// The app's `WindowGroup(for: RoomWindowID.self)` presents one window per
/// value: opening a room that already has a window brings that window
/// forward. SwiftUI encodes the value for scene restoration, so the coded
/// form must stay stable: add new fields as optionals only.
public struct RoomWindowID: Codable, Hashable, Sendable {
    public let roomId: String

    public init(roomId: String) {
        self.roomId = roomId
    }
}

/// Whether a signed-in session exists, as a room window sees it.
public enum RoomWindowSession: Equatable, Sendable {
    /// The saved session is still being restored. A restored window waits
    /// here on relaunch before it looks up its room.
    case restoring
    /// The restore finished, or the session ended, and no client exists.
    case signedOut
    case signedIn
}

/// What the window's room lookup found.
public enum RoomWindowRoomLookup: Equatable {
    /// Neither the room list nor the client's store holds the room.
    case notFound
    /// The client holds the room, with the user's membership in it.
    case found(Membership)
}

/// Why a room window cannot show its room.
public enum RoomWindowUnavailableReason: Equatable, Sendable {
    /// No session: the user signed out, or the auth failed.
    case signedOut
    /// The room list loaded and the room is not in it.
    case notInRoomList
    /// The user left the room, or was kicked.
    case left
    case banned
}

/// What a single-room window shows (MATRIX-116).
///
/// `resolve(session:roomListLoaded:room:)` is a pure function of the
/// window's inputs, so the view re-derives it on every change and never
/// holds a stale phase. The room comes back on its own when it comes back
/// in the inputs (a rejoin, or a sign-in after a sign-out).
public enum RoomWindowPhase: Equatable, Sendable {
    /// No client yet: the session restore runs.
    case waitingForSession
    /// The client exists, but the room list has not loaded and the store
    /// does not hold the room yet.
    case lookingUpRoom
    /// The room's timeline and composer. Invited and knocked rooms show
    /// here too, because the room view has its own screens for them.
    case showingRoom
    case unavailable(RoomWindowUnavailableReason)

    /// Derives the window's phase.
    ///
    /// - Parameters:
    ///   - session: whether a signed-in client exists.
    ///   - roomListLoaded: whether the SDK room list finished its first
    ///     load (`RoomListServiceState.running`). Before that, a missing
    ///     room is still loading, not gone.
    ///   - room: what the lookup found.
    /// - Returns: the phase to show.
    ///
    /// ```swift
    /// RoomWindowPhase.resolve(session: .signedIn, roomListLoaded: false, room: .notFound)
    /// // .lookingUpRoom
    /// ```
    public static func resolve(
        session: RoomWindowSession,
        roomListLoaded: Bool,
        room: RoomWindowRoomLookup
    ) -> RoomWindowPhase {
        switch session {
        case .restoring:
            return .waitingForSession
        case .signedOut:
            return .unavailable(.signedOut)
        case .signedIn:
            break
        }

        switch room {
        case .notFound:
            return roomListLoaded ? .unavailable(.notInRoomList) : .lookingUpRoom
        case let .found(membership):
            switch membership {
            case .joined, .invited, .knocked:
                return .showingRoom
            case .left:
                return .unavailable(.left)
            case .banned:
                return .unavailable(.banned)
            }
        }
    }

    /// Whether the window should hold a live timeline for its room.
    /// Every other phase drops it, so no SDK timeline outlives its room or
    /// its session.
    public var keepsTimeline: Bool {
        self == .showingRoom
    }
}

/// The main window's sidebar width across launches (MATRIX-116, D-8).
///
/// The sidebar measures its column and stores the width. A new main window
/// starts its column at the stored width through
/// `navigationSplitViewColumnWidth(min:ideal:max:)`.
public enum SidebarWidthMemory {
    /// The `UserDefaults` key. App-wide, not per window, so a new window
    /// (⌥⌘N) opens at the width the user last chose.
    public static let storageKey = "MainWindow.sidebarWidth"

    /// The ideal column width to start a window with.
    ///
    /// - Parameters:
    ///   - stored: the stored width, or `nil` before the first store.
    ///   - minimum: the column's minimum width.
    ///   - defaultIdeal: the width to use when nothing usable is stored.
    /// - Returns: the stored width, never below `minimum`; else `defaultIdeal`.
    public static func idealWidth(stored: Double?, minimum: Double, defaultIdeal: Double) -> Double {
        guard let stored, stored.isFinite, stored > 0 else { return defaultIdeal }
        return max(stored, minimum)
    }

    /// The width to store for a measured column, or `nil` to store nothing.
    ///
    /// A collapsed or animating sidebar measures below its minimum. Such a
    /// width is not a choice the user made, so it is not stored.
    ///
    /// - Parameters:
    ///   - measured: the column's measured width.
    ///   - minimum: the column's minimum width.
    ///   - current: the width stored now, if any.
    /// - Returns: the whole-point width, or `nil` when it is unusable or
    ///   equal to `current`.
    public static func widthToStore(measured: Double, minimum: Double, current: Double?) -> Double? {
        guard measured.isFinite, measured >= minimum else { return nil }
        let rounded = measured.rounded()
        return rounded == current ? nil : rounded
    }
}
