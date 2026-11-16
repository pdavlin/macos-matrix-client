import Models
import SwiftUI

/// The "Refresh Custom Emoji" command as the reaction picker shows it
/// (MATRIX-161): the state of the last refresh and the action that starts one.
public struct ImagePackRefreshControl {
    /// The refresh in flight or its outcome, or nil when idle.
    public let status: ImagePackStore.RefreshStatus?
    /// Starts a refresh of the chat's workspace.
    public let action: @MainActor () -> Void

    public init(status: ImagePackStore.RefreshStatus?, action: @escaping @MainActor () -> Void) {
        self.status = status
        self.action = action
    }
}

/// The refresh button in the header of the picker's pack section
/// (MATRIX-161).
///
/// Idle, it is one small button. During a refresh the button is disabled and
/// "Refreshing…" shows beside it. After a refresh the text is the emoji count
/// or "Refresh failed", until the host clears the status. The text has no
/// spinner, so the header draws the same way each time.
struct ImagePackRefreshButton: View {
    let control: ImagePackRefreshControl

    /// The text beside the button, or nil when idle.
    static func statusText(_ status: ImagePackStore.RefreshStatus?) -> String? {
        switch status {
        case nil:
            nil
        case .busy:
            "Refreshing…"
        case let .loaded(emojiCount: count):
            "\(count) emoji"
        case .failed:
            "Refresh failed"
        }
    }

    var body: some View {
        let isBusy: Bool = control.status == .busy
        HStack(spacing: 4) {
            if let text = Self.statusText(control.status) {
                Text(verbatim: text)
                    .font(.system(size: 11))
                    .foregroundStyle(control.status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Button {
                control.action()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isBusy ? .tertiary : .secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .help("Refresh Custom Emoji")
            .accessibilityLabel(Text("Refresh Custom Emoji"))
        }
    }
}
