public protocol ThreadSummary {
    func numReplies() -> UInt64

    var description: String? { get }

    /// The people the thread chip shows, newest first (MATRIX-183). The SDK
    /// summary gives only the latest reply, so the SDK conformance gives its
    /// sender alone, or no one while that reply is not loaded. The chip
    /// shows at most `ThreadToken.chipMaxAvatars` of them.
    var repliers: [ThreadReplier] { get }
}

/// A person who replied in a thread, as the thread chip shows them
/// (MATRIX-183).
public struct ThreadReplier: UserProfile, Hashable, Sendable {
    public let userId: String
    public let displayName: String?
    public let avatarUrl: String?

    public init(userId: String, displayName: String?, avatarUrl: String?) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

public struct MockThreadSummary: ThreadSummary {
    public init() {}

    public func numReplies() -> UInt64 {
        4
    }

    public var description: String? {
        """
        This is a thread message, that is _very_ long.

        It event has multiple lines.
        """
    }

    public var repliers: [ThreadReplier] {
        [ThreadReplier(userId: "@cy:example.org", displayName: "Cy", avatarUrl: nil)]
    }
}
