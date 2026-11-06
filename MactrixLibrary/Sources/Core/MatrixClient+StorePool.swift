import Foundation

extension MatrixClient {
    /// The most SQLite connections the SDK may open per store (MATRIX-122).
    ///
    /// Left uncapped, a burst of concurrent reads grew the state and crypto
    /// pools to 60 connections each. Every connection holds the database and
    /// its write-ahead log open, so the app hit macOS's 256 open-file limit
    /// and the event cache failed with SQLite `CannotOpen` (14): no earlier
    /// messages loaded. SQLite allows one writer at a time, so a small pool
    /// costs little; `FileDescriptorLimit` also raises the open-file limit.
    static let storePoolMaxSize: UInt32 = 8
}
