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
    static let liveThreadList = Logger(subsystem: subsystem, category: "live-thread-list")
    static let timelineRowMapping = Logger(subsystem: subsystem, category: "timeline-row-mapping")
    static let SidebarRoom = Logger(subsystem: subsystem, category: "sidebar-room")

    static let viewCycle = Logger(subsystem: subsystem, category: "viewcycle")

    static let notification = Logger(subsystem: subsystem, category: "notification")

    static let utd = Logger(subsystem: subsystem, category: "utd")

    static let labels = Logger(subsystem: subsystem, category: "labels")

    static let mergedChats = Logger(subsystem: subsystem, category: "merged-chats")

    static let inbox = Logger(subsystem: subsystem, category: "inbox")

    static let bookmarks = Logger(subsystem: subsystem, category: "bookmarks")

    static let scheduled = Logger(subsystem: subsystem, category: "scheduled")

    static let threadFollow = Logger(subsystem: subsystem, category: "thread-follow")
}

/// Signposts for the timeline measures (MATRIX-182): the member fetch when a
/// timeline opens, and the diffs that the timeline applies. The category is
/// "timeline-perf". docs/research/timeline-perf-2026-11.md tells how to
/// record them.
extension OSSignposter {
    static let timeline = OSSignposter(subsystem: applicationID, category: "timeline-perf")
}
