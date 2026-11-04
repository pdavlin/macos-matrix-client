import Foundation

/// The composer's Return-key policy.
///
/// The default is decision D-1 (approved 2026-09-01): Enter sends,
/// Shift-Enter inserts a newline, Cmd-Enter also sends. M2 (MATRIX-100) makes
/// this configurable through `SendMode`; the alternative mode sends on
/// Cmd-Enter only, so Enter and Shift-Enter both insert a newline.
///
/// Pure decision logic, kept out of the AppKit text view so the rule that
/// defines the send gesture is unit-tested rather than buried in `keyDown`.
public enum ComposerKeyDecision {
    /// What the composer should do with a key press.
    public enum Action: Equatable, Sendable {
        /// Submit the message.
        case send
        /// Let the text view handle the key (insert newline, commit IME
        /// composition, ...).
        case passthrough
    }

    /// Which Return-key gesture sends a message.
    ///
    /// `String`-backed so it can be stored directly with `@AppStorage` under
    /// `storageKey`. The raw values are persisted user settings: do not rename
    /// them.
    public enum SendMode: String, CaseIterable, Sendable {
        /// D-1 default: Enter sends, Shift-Enter inserts a newline,
        /// Cmd-Enter also sends.
        case enterSends
        /// Cmd-Enter sends; Enter and Shift-Enter insert a newline.
        case commandEnterSends

        /// `UserDefaults` key backing the user's choice. Same naming style as
        /// `TypographyToken.fontSizeStorageKey`.
        public static let storageKey = "composerSendMode"

        /// Mode used when the user has never chosen one.
        public static let defaultMode: SendMode = .enterSends
    }

    /// Decides the action for a key press in the composer.
    ///
    /// - Parameters:
    ///   - isReturnKey: whether the key is Return or keypad Enter.
    ///   - hasMarkedText: whether an input method holds an uncommitted
    ///     composition. Return then commits the composition and must never
    ///     send, in either mode.
    ///   - shift: Shift is held (newline in `.enterSends`).
    ///   - command: Command is held (send in every mode, matching the
    ///     inherited Cmd-Enter shortcut).
    ///   - otherModifiers: any modifier besides Shift/Command is held
    ///     (Option-Return and Control-Return stay text-view gestures).
    ///   - mode: the user's send mode. Defaults to `.enterSends` (D-1).
    public static func action(
        isReturnKey: Bool,
        hasMarkedText: Bool,
        shift: Bool,
        command: Bool,
        otherModifiers: Bool,
        mode: SendMode = .enterSends
    ) -> Action {
        guard isReturnKey else { return .passthrough }
        if hasMarkedText { return .passthrough }
        if otherModifiers { return .passthrough }
        if command { return .send }
        switch mode {
        case .enterSends:
            return shift ? .passthrough : .send
        case .commandEnterSends:
            return .passthrough
        }
    }
}
