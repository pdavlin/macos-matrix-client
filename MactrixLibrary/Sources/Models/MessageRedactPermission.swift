import Foundation

/// What the signed-in account may redact in one room (MATRIX-110).
///
/// `Core` reads it from the room's power levels once per room open, and again
/// when the room info changes. Rows read the stored value, so a hover never
/// calls the SDK.
public struct MessageRedactPermission: Equatable, Sendable {
    /// The account may redact its own messages.
    public var canRedactOwn: Bool
    /// The account may redact other people's messages (a moderator).
    public var canRedactOther: Bool

    public init(canRedactOwn: Bool, canRedactOther: Bool) {
        self.canRedactOwn = canRedactOwn
        self.canRedactOther = canRedactOther
    }

    /// No redaction. The value until the power levels load, and after a
    /// failed read.
    public static let none = Self(canRedactOwn: false, canRedactOther: false)

    /// Whether the account may redact a message.
    /// - Parameter isOwn: Whether the account sent the message.
    public func allows(isOwn: Bool) -> Bool {
        isOwn ? canRedactOwn : canRedactOther
    }
}

/// Rules for the redaction request itself (MATRIX-110).
public enum MessageRedaction {
    /// The reason to send with a redaction: the typed text without leading
    /// and trailing white space, or nil when nothing is left. The SDK then
    /// sends no reason field at all.
    public static func normalizedReason(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
