import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!

    static let matrixClient = Logger(subsystem: subsystem, category: "matrix-client")

    static let timelineTableView = Logger(subsystem: subsystem, category: "timeline-table-view")
    static let timelineRowMapping = Logger(subsystem: subsystem, category: "timeline-row-mapping")
    static let chatTextView = Logger(subsystem: subsystem, category: "chat-text-view")

    static let viewCycle = Logger(subsystem: subsystem, category: "viewcycle")
}
