import Models
import SwiftUI

/// Settings > Composer: chooses which Return-key gesture sends a message
/// (MATRIX-100).
///
/// The choice is stored with `@AppStorage` under
/// `ComposerKeyDecision.SendMode.storageKey`; the composer text view reads the
/// same key, so a change applies to open composers at once. The send rule
/// itself lives in `ComposerKeyDecision`; this view only edits the setting.
///
/// The view lives in the UI library rather than the app target so its
/// snapshot test exercises the shipped view.
public struct ComposerSettingsView: View {
    @AppStorage private var sendMode: ComposerKeyDecision.SendMode

    /// - Parameter store: the defaults store to read and write. `nil` uses
    ///   `UserDefaults.standard`; tests pass an isolated suite.
    public init(store: UserDefaults? = nil) {
        _sendMode = AppStorage(
            wrappedValue: ComposerKeyDecision.SendMode.defaultMode,
            ComposerKeyDecision.SendMode.storageKey,
            store: store
        )
    }

    public var body: some View {
        Form {
            Picker("Send messages with", selection: $sendMode) {
                ForEach(ComposerKeyDecision.SendMode.allCases, id: \.self) { mode in
                    Text(Self.label(for: mode))
                        .tag(mode)
                }
            }
            .radioGroupPickerStyle()
        }
    }

    /// The radio-button label for each mode. Cmd-Return sends in both modes,
    /// so each label names only the gesture that differs.
    private static func label(for mode: ComposerKeyDecision.SendMode) -> LocalizedStringKey {
        switch mode {
        case .enterSends:
            "Return (Shift-Return adds a new line)"
        case .commandEnterSends:
            "Command-Return (Return adds a new line)"
        }
    }
}
