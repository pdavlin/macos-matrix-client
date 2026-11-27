import Models
import SwiftUI
import Tokens

/// The header strip of the thread panel (MATRIX-183): the title "Thread",
/// a subtitle with the room and the reply count, the Follow control
/// (MATRIX-261), and the close button on the trailing edge, as in a macOS
/// inspector. The strip is the navigation layer, so it keeps its material.
public struct ThreadTimelineHeader: View {
    let roomName: String?
    let replyCount: Int?
    let follow: ThreadFollowControl?
    let onFollow: () -> Void
    let dismiss: () -> Void

    /// - Parameters:
    ///   - roomName: the room's display name, or nil.
    ///   - replyCount: the thread's reply count, or nil while it is not
    ///     known.
    ///   - follow: the Follow control, or nil for no control.
    ///   - onFollow: a click on the Follow control.
    ///   - dismiss: closes the panel.
    public init(
        roomName: String?,
        replyCount: Int?,
        follow: ThreadFollowControl? = nil,
        onFollow: @escaping () -> Void = {},
        dismiss: @escaping () -> Void
    ) {
        self.roomName = roomName
        self.replyCount = replyCount
        self.follow = follow
        self.onFollow = onFollow
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
                if let follow {
                    Button(action: onFollow) {
                        Label(follow.title, systemImage: follow.systemImage)
                    }
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(follow.isFollowed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .disabled(!follow.isEnabled)
                    .help(follow.help)
                }
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
        ThreadTimelineHeader(roomName: "#general", replyCount: 4, follow: ThreadFollowControl(state: .followed)) {}
        Text("Body")
            .frame(maxWidth: .infinity, maxHeight: 40)
            .background(.white)
    }
}
