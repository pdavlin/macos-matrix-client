import Foundation

/// Naming rules for media files saved into the user's Downloads folder.
public enum MediaDownloads {
    /// A filename safe to create inside a directory.
    ///
    /// Path separators and colons become dashes, surrounding whitespace is
    /// trimmed, leading dots are dropped (a bridged filename must not produce
    /// a hidden file), and an empty result falls back to "download".
    public static func sanitizedFilename(_ raw: String) -> String {
        var name = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") {
            name.removeFirst()
        }
        return name.isEmpty ? "download" : name
    }

    /// The first destination in `directory` that does not already exist:
    /// `name.ext`, then `name (2).ext`, `name (3).ext`, and so on.
    ///
    /// Existence is asked through `fileExists` so the rule stays pure and
    /// testable; the caller passes `FileManager` in production.
    public static func uniqueDestination(
        directory: URL,
        filename: String,
        fileExists: (URL) -> Bool
    ) -> URL {
        let sanitized = sanitizedFilename(filename)
        let base = (sanitized as NSString).deletingPathExtension
        let ext = (sanitized as NSString).pathExtension

        func candidate(_ attempt: Int) -> URL {
            let name: String = if attempt <= 1 {
                sanitized
            } else if ext.isEmpty {
                "\(base) (\(attempt))"
            } else {
                "\(base) (\(attempt)).\(ext)"
            }
            return directory.appending(path: name, directoryHint: .notDirectory)
        }

        var attempt = 1
        var url = candidate(attempt)
        while fileExists(url), attempt < 1000 {
            attempt += 1
            url = candidate(attempt)
        }
        return url
    }
}
