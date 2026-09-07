import SwiftUI
import Tokens

/// The typing-indicator row, rendered at the newest end of the timeline (D-3).
///
/// Wraps `UserTypingIndicator` in the timeline's row metrics so the indicator
/// lines up with the message column above it.
public struct TypingIndicatorRow: View {
    let names: [String]

    public init(names: [String]) {
        self.names = names
    }

    public var body: some View {
        HStack(spacing: 0) {
            UserTypingIndicator(names: names)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DensityToken.rowHorizontalPadding)
        .padding(.vertical, DensityToken.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The back-pagination activity row, rendered at the oldest end (D-2).
///
/// Infinite scroll stays, so the only feedback that older messages are on the
/// way is this row. It occupies real height, which also keeps the oldest end
/// from snapping while a batch lands.
public struct PaginationActivityRow: View {
    /// Set by snapshot tests to swap the indeterminate spinner for a static
    /// substitute. An indeterminate `ProgressView` animates on its own timer,
    /// so a capture would land on a random phase. Production never sets this.
    @Environment(\.usesStaticProgressIndicators) private var usesStaticActivity

    public init() {}

    public var body: some View {
        HStack(spacing: DensityToken.reactionPadding * 2) {
            Spacer(minLength: 0)
            if usesStaticActivity {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text("Loading earlier messages")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DensityToken.rowHorizontalPadding)
        .padding(.vertical, DensityToken.rowVerticalPadding * 2)
        .frame(maxWidth: .infinity)
    }
}

public extension EnvironmentValues {
    /// Whether message rows show read receipts.
    ///
    /// D-3 renders receipts in direct rooms only: in a group room the avatar
    /// pile changes on every member's read and carries no information the
    /// reader wants. The timeline container sets this from the room's direct
    /// flag; the default keeps previews and existing call sites unchanged.
    @Entry var timelineShowsReadReceipts: Bool = true
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        PaginationActivityRow()
        TypingIndicatorRow(names: ["John Doe"])
        TypingIndicatorRow(names: ["John Doe", "Person"])
    }
    .frame(width: 400)
    .background(Color(NSColor.controlBackgroundColor))
}
