import Foundation

/// The composer's Return-key policy (decision D-1, approved 2026-09-01):
/// Enter sends, Shift-Enter inserts a newline, Cmd-Enter also sends.
///
/// Pure decision logic, kept out of the AppKit text view so the rule that
/// defines the send gesture is unit-tested rather than buried in `keyDown`.
/// M2 makes the default configurable; this type is where that setting will
/// land.
public enum ComposerKeyDecision {
    /// What the composer should do with a key press.
    public enum Action: Equatable, Sendable {
        /// Submit the message.
        case send
        /// Let the text view handle the key (insert newline, commit IME
        /// composition, ...).
        case passthrough
    }

    /// Decides the action for a key press in the composer.
    ///
    /// - Parameters:
    ///   - isReturnKey: whether the key is Return or keypad Enter.
    ///   - hasMarkedText: whether an input method holds an uncommitted
    ///     composition. Return then commits the composition and must never
    ///     send.
    ///   - shift: Shift is held (D-1: newline).
    ///   - command: Command is held (send, matching the inherited Cmd-Enter
    ///     shortcut).
    ///   - otherModifiers: any modifier besides Shift/Command is held
    ///     (Option-Return and Control-Return stay text-view gestures).
    public static func action(
        isReturnKey: Bool,
        hasMarkedText: Bool,
        shift: Bool,
        command: Bool,
        otherModifiers: Bool
    ) -> Action {
        guard isReturnKey else { return .passthrough }
        if hasMarkedText { return .passthrough }
        if otherModifiers { return .passthrough }
        if command { return .send }
        if shift { return .passthrough }
        return .send
    }
}
