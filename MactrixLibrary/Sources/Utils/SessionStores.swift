import Foundation

public enum SessionStores {
    /// Returns the subdirectories of `parent` whose name is not `keptID`.
    ///
    /// Every login attempt creates a fresh store directory named by a random
    /// store ID; attempts that never complete leave theirs behind. Once a
    /// session is restored, any sibling of its store directory is an orphan.
    public static func orphanedDirectories(
        in parent: URL,
        keeping keptID: String,
        fileManager: FileManager = .default
    ) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents.filter { url in
            guard url.lastPathComponent != keptID else { return false }
            return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}
