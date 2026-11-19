import Foundation

/// A link to one post on X or Bluesky, which a plain click on a message body
/// link opens in the post peek popover (MATRIX-201).
///
/// The rules follow post-peek (https://github.com/tsvb/post-peek, MIT),
/// which this feature re-implements:
/// - X: `x.com`, `twitter.com`, `mobile.twitter.com` (and `www.` and
///   `mobile.x.com`), path `/<user>/status/<id>` or `/i/web/status/<id>`,
///   with any path, query or fragment after the ID. The user is 1 to 20
///   letters, digits and underscores. The ID is 1 to 25 digits.
/// - Bluesky: `bsky.app/profile/<handle or DID>/post/<record key>`, with any
///   path, query or fragment after the key. A percent-encoded DID decodes
///   first.
public enum PostPeekLink: Hashable, Sendable {
    case x(id: String)
    case bluesky(actor: String, rkey: String)

    public enum Site: Sendable {
        case x, bluesky

        /// The name of the site, for "Open on <name>".
        public var name: String {
            switch self {
            case .x: "X"
            case .bluesky: "Bluesky"
            }
        }
    }

    public var site: Site {
        switch self {
        case .x: .x
        case .bluesky: .bluesky
        }
    }

    /// The post on the web, for the browser when the peek fails.
    public var webURL: URL {
        let string = switch self {
        case let .x(id): "https://x.com/i/web/status/\(id)"
        case let .bluesky(actor, rkey): "https://bsky.app/profile/\(actor)/post/\(rkey)"
        }
        // The parts passed the character checks of `init`, so the string is
        // a valid URL.
        return URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let parts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        if Self.xHosts.contains(host) {
            guard let link = Self.xLink(parts) else { return nil }
            self = link
        } else if host == "bsky.app" {
            guard let link = Self.blueskyLink(parts) else { return nil }
            self = link
        } else {
            return nil
        }
    }

    /// The Bluesky post of an `at://<actor>/app.bsky.feed.post/<rkey>` URI.
    public init?(atURI uri: String) {
        let prefix = "at://"
        guard uri.hasPrefix(prefix) else { return nil }
        let parts = uri.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[1] == "app.bsky.feed.post",
              Self.isBlueskyActor(parts[0]), Self.isRecordKey(parts[2])
        else { return nil }
        self = .bluesky(actor: parts[0], rkey: parts[2])
    }

    static let xHosts: Set = ["x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"]

    private static func xLink(_ parts: [String]) -> PostPeekLink? {
        let rest: ArraySlice<String>
        if parts.count >= 4, parts[0] == "i", parts[1] == "web" {
            rest = parts[2...]
        } else if parts.count >= 3, isXUser(parts[0]) {
            rest = parts[1...]
        } else {
            return nil
        }
        guard let status = rest.first, status == "status" || status == "statuses" else { return nil }
        let id = rest.dropFirst().first ?? ""
        guard (1 ... 25).contains(id.count), id.allSatisfy(\.isASCIIDigit) else { return nil }
        return .x(id: id)
    }

    private static func blueskyLink(_ parts: [String]) -> PostPeekLink? {
        guard parts.count >= 4, parts[0] == "profile", parts[2] == "post",
              parts[1].count <= 253,
              let actor = parts[1].removingPercentEncoding,
              isBlueskyActor(actor), isRecordKey(parts[3])
        else { return nil }
        return .bluesky(actor: actor, rkey: parts[3])
    }

    private static func isXUser(_ user: String) -> Bool {
        (1 ... 20).contains(user.count) && user.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// A DID (`did:<method>:<id>`) or a handle (letters, digits, dots and
    /// hyphens).
    static func isBlueskyActor(_ actor: String) -> Bool {
        guard !actor.isEmpty, actor.count <= 253 else { return false }
        if actor.hasPrefix("did:") {
            let parts = actor.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, !parts[1].isEmpty, !parts[2].isEmpty else { return false }
            return parts[1].allSatisfy { $0.isASCII && $0.isLowercase }
                && parts[2].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._:%-".contains($0)) }
        }
        return actor.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    /// A record key: 1 to 512 letters, digits and `._~:-`.
    static func isRecordKey(_ key: String) -> Bool {
        (1 ... 512).contains(key.count) && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._~:-".contains($0)) }
    }
}

/// The switch of the post peek (MATRIX-201, Settings > Appearance).
///
/// Stored with `@AppStorage` under `storageKey`. The key is a persisted user
/// setting: do not rename it. A key that was never written reads as the
/// default, on. Off, X and Bluesky links open in the browser.
public enum PostPeekPreferences {
    /// `UserDefaults` key of the switch.
    public static let storageKey = "peeksPostLinks"
    /// The value when the user never changed it.
    public static let defaultValue = true

    /// The stored value, or the default.
    public static func isOn(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
