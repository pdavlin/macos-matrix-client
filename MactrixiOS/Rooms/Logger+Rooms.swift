import Foundation
import OSLog

/// Log categories for the iOS room list and settings (MATRIX-84).
extension Logger {
    private static let roomsSubsystem = Bundle.main.bundleIdentifier ?? "io.davlin.matrixclient.ios"

    static let roomList = Logger(subsystem: roomsSubsystem, category: "room-list")
    static let settings = Logger(subsystem: roomsSubsystem, category: "settings")
}
