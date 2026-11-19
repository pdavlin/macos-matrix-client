import Models
import SwiftUI
import Tokens

/// The header strip of the thread panel (MATRIX-183): the title "Thread",
/// a subtitle with the room and the reply count, and the close button on the
/// trailing edge, as in a macOS inspector. The strip is the navigation layer,
/// so it keeps its material.
public struct ThreadTimelineHeader: View {
    let roomName: String?
    let replyCount: Int?
    let dismiss: () -> Void

    /// - Parameters:
    ///   - roomName: the room's display name, or nil.
    ///   - replyCount: the thread's reply count, or nil while it is not
    ///     known.
    ///   - dismiss: closes the panel.
    public init(roomName: String?, replyCount: Int?, dismiss: @escaping () -> Void) {
        self.roomName = roomName
        self.replyCount = replyCount
        self.dismiss = dismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: ThreadToken.headerLineSpacing) {
                    Text(ThreadPanelHeaderText.title)
                        .font(.headline)
                    if let subtitle = ThreadPanelHeaderText.subtitle(roomName: roomName, replyCount: replyCount) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Label("Close Thread", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .help("Close Thread")
            }
            .padding(ThreadToken.headerPadding)
            Divider()
        }
        .background(.thinMaterial)
    }
}

#Preview {
    VStack(spacing: 0) {
        ThreadTimelineHeader(roomName: "#general", replyCount: 4) {}
        Text("Body")
            .frame(maxWidth: .infinity, maxHeight: 40)
            .background(.white)
    }
}
