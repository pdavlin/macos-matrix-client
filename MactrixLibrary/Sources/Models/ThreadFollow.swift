import Foundation

// MARK: - Server support (MATRIX-261)

/// Whether the homeserver handles MSC4306 thread subscriptions, as far as the
/// app has seen (MATRIX-261).
///
/// The FFI has no read of the server's `org.matrix.msc4306` flag. And
/// `Room.fetchThreadSubscription` returns nil both for a thread with no
/// subscription and for a server without MSC4306: the SDK maps every 404 to
/// nil. So the app keeps its own evidence (`ThreadSubscriptionSupportRecord`):
/// - a read that returns a subscription, or a change that the server accepts,
///   can only come from a server with MSC4306: `supported`;
/// - a change that the server refuses with `M_UNRECOGNIZED` (it does not know
///   the endpoint): `unsupported`;
/// - no evidence: `unknown`.
///
/// The banner filter and the own-root rule act only on `supported`. The
/// Follow control works in every state: a click is also the first evidence.
public enum ThreadSubscriptionSupport: Equatable, Sendable {
    case unknown
    case supported
    case unsupported
}

/// One answer of the server that tells whether it handles MSC4306.
public enum ThreadSubscriptionEvidence: Equatable, Sendable {
    /// `fetchThreadSubscription` returned a subscription.
    case subscriptionRead
    /// `setThreadSubscription` completed.
    case changeAccepted
    /// `setThreadSubscription` failed with `M_UNRECOGNIZED`.
    case endpointUnrecognized
}

/// The evidence the app keeps about MSC4306 on the server, and the rule that
/// resets the SDK's `/versions` cache one time (MATRIX-261).
///
/// The SDK keeps the server's `/versions` answer for 24 hours, and reads the
/// MSC4306 flag at launch only. When the server gains MSC4306, the SDK does
/// not see it for up to a day. The reset rule: the first evidence of support
/// after a time without it (no evidence, or a refusal) asks for one
/// `Client.resetSupportedVersions()`. The next launch then reads `/versions`
/// again. A refusal arms the rule again, so a server that loses MSC4306 and
/// gets it back gets one more reset. A normal launch never resets.
///
/// Evidence of support expires after `supportLifetime`, so a server that
/// loses MSC4306 does not keep the banner filter on for longer than that.
/// Each new read of a subscription renews it.
public struct ThreadSubscriptionSupportRecord: Codable, Equatable, Sendable {
    /// How long one piece of evidence of support holds.
    public static let supportLifetime: TimeInterval = 7 * 24 * 60 * 60

    public private(set) var lastSupportedAt: Date?
    public private(set) var lastUnsupportedAt: Date?
    /// True after the reset for the current support. A refusal sets it to
    /// false again.
    public private(set) var versionsResetDone: Bool

    public init(lastSupportedAt: Date? = nil, lastUnsupportedAt: Date? = nil, versionsResetDone: Bool = false) {
        self.lastSupportedAt = lastSupportedAt
        self.lastUnsupportedAt = lastUnsupportedAt
        self.versionsResetDone = versionsResetDone
    }

    /// The support at `now`. The newer piece of evidence wins.
    public func support(at now: Date) -> ThreadSubscriptionSupport {
        switch (lastSupportedAt, lastUnsupportedAt) {
        case (nil, nil):
            return .unknown
        case (nil, .some):
            return .unsupported
        case let (supported?, unsupported?) where unsupported >= supported:
            return .unsupported
        case let (supported?, _):
            return now.timeIntervalSince(supported) <= Self.supportLifetime ? .supported : .unknown
        }
    }

    /// Records one piece of evidence.
    ///
    /// - Returns: true if the app must call `Client.resetSupportedVersions()`
    ///   now. That is true one time for each change to support.
    public mutating func record(_ evidence: ThreadSubscriptionEvidence, at now: Date) -> Bool {
        switch evidence {
        case .subscriptionRead, .changeAccepted:
            lastSupportedAt = now
            guard !versionsResetDone else { return false }
            versionsResetDone = true
            return true
        case .endpointUnrecognized:
            lastUnsupportedAt = now
            versionsResetDone = false
            return false
        }
    }

    /// The reset did not complete: the next evidence of support asks again.
    public mutating func versionsResetFailed() {
        versionsResetDone = false
    }
}

// MARK: - Read

/// What the app knows of one thread's subscription.
public enum ThreadFollowRead: Equatable, Sendable {
    /// No read yet, or the cached read expired.
    case notRead
    /// The account follows the thread.
    case followed
    /// The account does not follow the thread, or the server has no MSC4306.
    case notFollowed
    /// The read failed (for example, no network).
    case failed
}

/// The reads of the last `lifetime` seconds, by thread root (MATRIX-261).
///
/// The banner filter reads a thread's state for each banner. A burst of
/// replies in one thread then costs one read for each `lifetime`. An SDK
/// follow (a mention, an own reply) shows within `lifetime`. The Follow
/// control writes its change here at once.
public struct ThreadFollowCache: Equatable, Sendable {
    public static let lifetime: TimeInterval = 30
    /// Above this count, a write removes the expired entries.
    static let limit = 200

    private struct Entry: Equatable, Sendable {
        let isFollowed: Bool
        let readAt: Date
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// The cached state of `root`, or `.notRead` if none is younger than
    /// `lifetime`.
    public func read(root: String, at now: Date) -> ThreadFollowRead {
        guard let entry = entries[root], now.timeIntervalSince(entry.readAt) < Self.lifetime else { return .notRead }
        return entry.isFollowed ? .followed : .notFollowed
    }

    public mutating func store(isFollowed: Bool, root: String, at now: Date) {
        entries[root] = Entry(isFollowed: isFollowed, readAt: now)
        if entries.count > Self.limit {
            entries = entries.filter { now.timeIntervalSince($0.value.readAt) < Self.lifetime }
        }
    }

    public mutating func remove(root: String) {
        entries[root] = nil
    }
}

// MARK: - Control

/// The state of the Follow control of one thread (MATRIX-261): the Mac
/// thread panel header and the iOS thread screen.
///
/// It comes from `Room.fetchThreadSubscription`, read when the thread opens
/// and again after each change. The FFI has no listener for a change.
public enum ThreadFollowState: Equatable, Sendable {
    /// The first read is not done.
    case reading
    case followed
    case notFollowed
    /// A change is on its way to the server.
    case changing(toFollowed: Bool)

    /// The state after a read. A failed read shows as not followed: the
    /// control stays off, with no alert.
    public init(read: ThreadFollowRead) {
        switch read {
        case .notRead:
            self = .reading
        case .followed:
            self = .followed
        case .notFollowed, .failed:
            self = .notFollowed
        }
    }
}

/// How the Follow control draws a state, and what a click asks for.
public struct ThreadFollowControl: Equatable, Sendable {
    public static let followTitle = "Follow Thread"
    public static let unfollowTitle = "Unfollow Thread"
    public static let followHelp = "Get notifications for new replies in this thread, on every device."
    /// The second sentence is the limit of upstream SDK issue #6735.
    public static let unfollowHelp = "Stop notifications for new replies in this thread, on every device. "
        + "In All Messages rooms and DMs, the next reply follows it again."

    /// The action, for the label and VoiceOver.
    public let title: String
    /// The state: a filled bell while the account follows the thread.
    public let systemImage: String
    /// The tooltip on the Mac, the accessibility hint on iOS.
    public let help: String
    public let isEnabled: Bool
    public let isFollowed: Bool
    /// What a click asks for: true follows, false unfollows.
    public let follows: Bool

    public init(state: ThreadFollowState) {
        let isFollowed: Bool = switch state {
        case .reading, .notFollowed:
            false
        case .followed:
            true
        case let .changing(toFollowed):
            toFollowed
        }
        self.isFollowed = isFollowed
        title = isFollowed ? Self.unfollowTitle : Self.followTitle
        systemImage = isFollowed ? "bell.fill" : "bell"
        help = isFollowed ? Self.unfollowHelp : Self.followHelp
        isEnabled = state == .followed || state == .notFollowed
        follows = !isFollowed
    }
}

// MARK: - Banner filter

/// Whether an in-process notification shows a banner, by the thread's follow
/// state (MATRIX-261).
///
/// The server's push rules (MSC4306) send no push for a reply in a thread
/// that the account does not follow. The SDK's in-process notifications do
/// not use that rule (no thread check in the base sync push context), so the
/// app applies it, like the MATRIX-77 label mute. A mention always shows: the
/// server's mention rules come before the thread rules. Remove this rule when
/// the SDK's push context gets the thread check.
public enum ThreadBannerRule {
    public enum Decision: Equatable, Sendable {
        case show
        /// The caller reads the thread's state, then decides again.
        case readFollowState
        case drop
    }

    /// - Parameters:
    ///   - threadRoot: the thread of the event, or nil for an event that is
    ///     in no thread.
    ///   - hasMention: the SDK's `NotificationItem.hasMention`.
    ///   - support: the server's MSC4306 support. Only `supported` filters,
    ///     so a server without MSC4306 keeps every banner.
    ///   - read: the thread's state, `.notRead` before the read.
    public static func decide(
        threadRoot: String?,
        hasMention: Bool?,
        support: ThreadSubscriptionSupport,
        read: ThreadFollowRead
    ) -> Decision {
        guard threadRoot != nil, support == .supported, hasMention != true else { return .show }
        switch read {
        case .notRead:
            return .readFollowState
        case .followed, .failed:
            return .show
        case .notFollowed:
            return .drop
        }
    }
}

// MARK: - Own root rule

/// One message of the account in a room timeline, with its thread's reply
/// count (0 when it has no thread).
public struct OwnRootSighting: Equatable, Sendable {
    public let eventId: String
    public let replyCount: Int

    public init(eventId: String, replyCount: Int) {
        self.eventId = eventId
        self.replyCount = replyCount
    }
}

/// Finds the moment the first thread reply to an own message arrives, in one
/// room timeline (MATRIX-261).
///
/// Only a change that the timeline shows counts: a message seen with no
/// replies, then with replies. A message that a timeline loads with replies
/// already (history) does not count. So the rule never acts on an old thread
/// that Patrick unfollowed on another device.
public struct OwnRootReplyWatch: Equatable, Sendable {
    private var awaitingFirstReply: Set<String> = []

    public init() {}

    /// - Parameter sightings: every own message of the timeline now.
    /// - Returns: the messages whose first reply arrived since the last call,
    ///   in the order of `sightings`.
    public mutating func observe(_ sightings: [OwnRootSighting]) -> [String] {
        var awaiting = Set<String>()
        var arrived: [String] = []
        for sighting in sightings {
            if sighting.replyCount == 0 {
                awaiting.insert(sighting.eventId)
            } else if awaitingFirstReply.contains(sighting.eventId) {
                arrived.append(sighting.eventId)
            }
        }
        awaitingFirstReply = awaiting
        return arrived
    }
}

/// The own-root rule (MATRIX-261, the orchestrator's default): when the first
/// reply to an own message arrives, the app follows that thread one time.
///
/// MSC4306 has no party that follows a thread for its root author. The rule
/// is app policy over the SDK's `setThreadSubscription`. The guards against
/// undoing an Unfollow:
/// - a root that the app handled on this device (the rule followed it, a read
///   showed it followed, or Patrick used the Follow control) is skipped;
/// - a fresh read that shows a subscription skips it.
/// A read cannot tell "unfollowed" from "never followed" (both are nil), so
/// the handled set and `OwnRootReplyWatch` carry the guard.
public enum OwnRootFollowRule {
    public enum Decision: Equatable, Sendable {
        /// The caller reads the thread's state, then decides again.
        case readFollowState
        case follow
        case skip(SkipReason)
    }

    public enum SkipReason: Equatable, Sendable {
        case serverWithoutThreadSubscriptions
        case alreadyHandled
        case alreadyFollowed
        case readFailed
    }

    public static func decide(support: ThreadSubscriptionSupport, isHandled: Bool, read: ThreadFollowRead) -> Decision {
        guard support == .supported else { return .skip(.serverWithoutThreadSubscriptions) }
        guard !isHandled else { return .skip(.alreadyHandled) }
        switch read {
        case .notRead:
            return .readFollowState
        case .followed:
            return .skip(.alreadyFollowed)
        case .notFollowed:
            return .follow
        case .failed:
            return .skip(.readFailed)
        }
    }
}

/// The thread roots that the own-root rule must not act on again, on this
/// device (MATRIX-261). Oldest first; above `limit` the oldest drops.
public struct ThreadFollowHandledRoots: Codable, Equatable, Sendable {
    public static let limit = 500

    public private(set) var roots: [String]

    public init(roots: [String] = []) {
        self.roots = roots
    }

    public func contains(_ root: String) -> Bool {
        roots.contains(root)
    }

    /// - Returns: false if `root` was in the set already.
    @discardableResult
    public mutating func insert(_ root: String) -> Bool {
        guard !roots.contains(root) else { return false }
        roots.append(root)
        if roots.count > Self.limit {
            roots.removeFirst(roots.count - Self.limit)
        }
        return true
    }
}
