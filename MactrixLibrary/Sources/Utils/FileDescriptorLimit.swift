import Darwin
import Foundation

/// The process's open-file limit (MATRIX-122).
///
/// macOS starts apps with a soft limit of 256 open files. The SDK keeps one
/// SQLite connection pool per store, and every connection holds the database
/// file and its write-ahead log open. Under a burst of concurrent reads the
/// pools grew to 60 connections each for the state and crypto stores (about
/// 240 files), so the event cache could not open its database at all: SQLite
/// `CannotOpen` (14), and no earlier messages loaded. The store pools are now
/// capped (`MatrixClient.clientBuilder`), and this raises the soft limit as a
/// margin for sockets, media files, and other handles.
public enum FileDescriptorLimit {
    /// The soft limit the app asks for.
    public static let desiredSoftLimit: rlim_t = 4096

    /// The soft limit to set: the desired one, never above the hard limit and
    /// never below the current soft limit.
    public static func target(currentSoft: rlim_t, hard: rlim_t, desired: rlim_t = desiredSoftLimit) -> rlim_t {
        max(currentSoft, min(desired, hard))
    }

    /// Raises the soft limit for this process. Returns the soft limits before
    /// and after, or nil when the limit cannot be read or set.
    @discardableResult
    public static func raiseSoftLimit() -> (before: rlim_t, after: rlim_t)? {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return nil }
        let before: rlim_t = limit.rlim_cur
        let wanted: rlim_t = target(currentSoft: before, hard: limit.rlim_max)
        guard wanted != before else { return (before, before) }
        limit.rlim_cur = wanted
        guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else { return nil }
        return (before, wanted)
    }
}
