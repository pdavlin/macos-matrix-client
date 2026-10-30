import Foundation
import OSLog

/// The bundle identifier. It names the per-session data and cache folders.
let applicationID = Bundle.main.bundleIdentifier ?? "io.davlin.matrixclient"

/// Log categories for the shared core. Same subsystem and category names as
/// the Mac app, so `log show` predicates keep working.
extension Logger {
    private static let subsystem = applicationID

    static let matrixClient = Logger(subsystem: subsystem, category: "matrix-client")
    static let windowState = Logger(subsystem: subsystem, category: "window-state")

    static let liveRoom = Logger(subsystem: subsystem, category: "live-room")
    static let liveSpaceService = Logger(subsystem: subsystem, category: "live-space-service")
    static let liveSpaceRoomList = Logger(subsystem: subsystem, category: "live-space-room-list")
    static let liveTimeline = Logger(subsystem: subsystem, category: "live-timeline")
    static let timelineRowMapping = Logger(subsystem: subsystem, category: "timeline-row-mapping")
    static let SidebarRoom = Logger(subsystem: subsystem, category: "sidebar-room")

    static let viewCycle = Logger(subsystem: subsystem, category: "viewcycle")

    static let notification = Logger(subsystem: subsystem, category: "notification")

    static let utd = Logger(subsystem: subsystem, category: "utd")
}
