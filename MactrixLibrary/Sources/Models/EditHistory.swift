import Foundation

/// One version of an edited message, as the edit history lists it
/// (MATRIX-209).
///
/// The SDK reads the versions (`Timeline.editRevisions(eventId:)`) and
/// decrypts them. This type only orders and marks them for display. It is
/// generic over the message content, so the list rules run in unit tests
/// without SDK types; `Core` fills it with the SDK's message content.
public struct EditHistoryVersion<Message>: Identifiable {
    /// What one version shows.
    public enum Body {
        /// A message body. The app draws it with the timeline's text
        /// rendering.
        case message(Message)
        /// A version the crypto layer could not decrypt, with the cause the
        /// SDK assigned.
        case unableToDecrypt(UnableToDecryptCause)
        /// Content the history does not draw, as a short description.
        case other(String)
    }

    /// The version's place in the SDK's list, oldest first: 0 is the
    /// original.
    public let id: Int
    public let body: Body
    /// When the version was sent, or nil when the SDK has no time for it.
    public let date: Date?

    /// Whether this is the message as first sent.
    public var isOriginal: Bool {
        id == 0
    }

    public init(id: Int, body: Body, date: Date?) {
        self.id = id
        self.body = body
        self.date = date
    }

    /// The versions newest first.
    ///
    /// - Parameter revisions: The SDK's revisions in its order: the original,
    ///   then each edit in the order it was applied. Each has its body and
    ///   its timestamp in milliseconds since 1970.
    /// - Returns: The versions, newest first. The last one is the original.
    public static func newestFirst(_ revisions: [(body: Body, timestamp: UInt64?)]) -> [Self] {
        revisions.enumerated().reversed().map { index, revision in
            Self(
                id: index,
                body: revision.body,
                date: revision.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
            )
        }
    }
}

extension EditHistoryVersion.Body: Equatable where Message: Equatable {}
extension EditHistoryVersion.Body: Sendable where Message: Sendable {}
extension EditHistoryVersion: Equatable where Message: Equatable {}
extension EditHistoryVersion: Sendable where Message: Sendable {}

/// What the edit history popover shows (MATRIX-209).
public enum EditHistoryState<Message> {
    /// The SDK reads the versions.
    case loading
    /// The versions, newest first (`EditHistoryVersion.newestFirst(_:)`).
    case loaded([EditHistoryVersion<Message>])
    /// The SDK call failed. The app logs the error.
    case failed
}

extension EditHistoryState: Equatable where Message: Equatable {}
extension EditHistoryState: Sendable where Message: Sendable {}
