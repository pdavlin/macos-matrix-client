import Foundation

/// The wait before a tooltip shows (MATRIX-166 follow-up, 2026-11-16).
///
/// AppKit reads the wait from the user default `NSInitialToolTipDelay`
/// (an integer, milliseconds). The system has no per-view delay, so the value
/// applies to every tooltip of the app, not only to the reaction chips.
public enum ToolTipDelay {
    /// The user default that AppKit reads.
    public static let defaultsKey = "NSInitialToolTipDelay"

    /// The wait, in milliseconds, between the pointer coming to rest and the
    /// tooltip. It applies to every tooltip of the app. Patrick asked for
    /// about half of the system wait, so that the list of who reacted shows
    /// quickly (MATRIX-166 follow-up, 2026-11-16).
    public static let initialMilliseconds = 400

    /// The defaults the Mac app registers at launch.
    public static let registeredDefaults: [String: Int] = [defaultsKey: initialMilliseconds]

    /// Registers the delay as a fallback value. A value the user set with
    /// `defaults write` is in the app's own domain, and it wins.
    public static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: registeredDefaults)
    }
}
