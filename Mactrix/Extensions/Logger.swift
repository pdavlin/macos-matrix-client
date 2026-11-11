import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!

    static let matrixClient = Logger(subsystem: subsystem, category: "matrix-client")

    static let timelineTableView = Logger(subsystem: subsystem, category: "timeline-table-view")
    static let timelineRowMapping = Logger(subsystem: subsystem, category: "timeline-row-mapping")
    static let chatTextView = Logger(subsystem: subsystem, category: "chat-text-view")
    /// MATRIX-142 Wave 2: the merged chat view and its composer.
    static let mergedChatView = Logger(subsystem: subsystem, category: "merged-chat-view")

    static let viewCycle = Logger(subsystem: subsystem, category: "viewcycle")
}
