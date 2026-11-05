import Foundation
import OSLog

extension URL {
    /// Creates the session's cache folder if it is missing (MATRIX-122).
    ///
    /// The event cache store lives under Caches, which macOS or a cleanup tool
    /// can empty while the session lives on. The SDK does not create that
    /// folder again, so every back-pagination then fails with SQLite
    /// `CannotOpen` (14), "unable to open database file". The cache is
    /// disposable: an empty one refills from the server.
    ///
    /// Only the cache folder. Creating the data folder here would hide a
    /// missing store from the probe in `MatrixClient.attemptRestore`.
    static func ensureSessionCachesDirectory(for sessionID: String) {
        let caches = sessionCaches(for: sessionID)
        guard !FileManager.default.fileExists(atPath: caches.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            Logger.matrixClient.warning(
                "session cache folder was missing; created it again: \(sessionID, privacy: .public)"
            )
        } catch {
            Logger.matrixClient.error(
                "failed to create the session cache folder: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
