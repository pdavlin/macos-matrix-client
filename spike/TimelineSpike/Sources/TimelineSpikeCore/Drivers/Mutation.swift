import Foundation

/// One change to an already-loaded event.
///
/// The set is deliberately small and models the two things that break naive timelines:
/// a body whose height changes under an existing layout, and a reaction row that appears
/// or disappears below a bubble.
public enum Mutation: Sendable, Equatable {
    /// Replaces a text body. The driver guarantees the new line count differs from the old
    /// one, so every emitted edit forces a height change.
    case editText(EventID, newBody: TextBody)
    /// Adds a reaction key, or increments it when the key is already present.
    case addReaction(EventID, key: String)
    /// Decrements a reaction key, removing the row entry when the tally reaches zero.
    case removeReaction(EventID, key: String)

    public var target: EventID {
        switch self {
        case .editText(let id, _): id
        case .addReaction(let id, _): id
        case .removeReaction(let id, _): id
        }
    }

    public var kindName: String {
        switch self {
        case .editText: "edit"
        case .addReaction: "reaction+"
        case .removeReaction: "reaction-"
        }
    }
}
