import MatrixRustSDK
import Models
import SwiftUI
import Tokens
import UI

/// Stand-in for the app's `ChatMessageView`.
///
/// The container names this type from two places — the data source and the
/// offscreen measurement view — so it has to exist with the same signature.
/// The body mirrors the app's: the real `UI.MessageEventProfileView` header,
/// the real `UI.MessageEventBodyView` chrome (avatar, name, hover actions,
/// reaction strip, receipts), and a message body for the synthetic content.
///
/// What it cannot mirror is the app's *body* views: `FormattedBodyView` and
/// `MessageImageView` take SDK content the harness has no way to build. The
/// text body is a `Text` and the image body is a shape at the placeholder's
/// aspect ratio, which is what the AppKit candidate drew too.
struct ChatMessageView: View, UI.MessageEventActions {
    @AppStorage(TypographyToken.fontSizeStorageKey) private var fontSize = TypographyToken.defaultBaseFontSize

    let timeline: LiveTimeline?
    let event: MatrixRustSDK.EventTimelineItem
    let msg: MatrixRustSDK.MsgLikeContent
    let includeProfileHeader: Bool

    // The row's hover buttons call these. Nothing is sent anywhere; the point
    // of building them is that the buttons exist in the measured view tree.
    func toggleReaction(key _: String) {}
    func reply() {}
    func replyInThread() {}
    func pin() {}
    func focusUser() {}

    private var typography: TimelineTypography {
        TimelineTypography(base: CGFloat(fontSize))
    }

    @ViewBuilder
    private var message: some View {
        switch msg.kind {
        case let .message(content: content):
            switch content.msgType {
            case .image, .video, .gallery:
                SyntheticMediaBody(descriptor: content.body)
            default:
                Text(content.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .sticker:
            SyntheticMediaBody(descriptor: "")
        case .poll, .redacted, .unableToDecrypt, .liveLocation, .other:
            Text("Unsupported content")
                .italic()
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        if includeProfileHeader {
            UI.MessageEventProfileView(event: event, actions: self, imageLoader: nil)
                .font(.system(size: typography.base))
        }
        UI.MessageEventBodyView(
            event: event,
            focused: false,
            reactions: msg.reactions,
            actions: self,
            ownUserID: "@harness:spike",
            imageLoader: nil,
            roomMembers: timeline?.room.members ?? []
        ) {
            VStack(alignment: .leading, spacing: 10) {
                message
            }
        }
        .font(.system(size: typography.base))
        .environment(\.timelineTypography, typography)
    }
}

/// The stand-in for a media body: a shape at the aspect ratio the synthetic
/// placeholder asks for, clamped the way a real media row is.
///
/// Aspect ratio and intrinsic width ride in the body string because the SDK
/// content shapes the harness can build carry no image info. `SyntheticMediaBody`
/// parses them back out; see `SyntheticEventAdapter`.
struct SyntheticMediaBody: View {
    let descriptor: String

    private var aspectRatio: CGFloat {
        MediaGeometry.parse(descriptor)?.aspectRatio ?? 1.6
    }

    private var intrinsicWidth: CGFloat {
        MediaGeometry.parse(descriptor)?.intrinsicWidth ?? 320
    }

    var body: some View {
        RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
            .fill(Color.secondary.opacity(0.25))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: intrinsicWidth, maxHeight: MediaRowLayout.maxHeight(height: nil))
    }
}

/// Encodes and decodes the media geometry carried through the message body.
enum MediaGeometry {
    static let prefix = "spike-media:"

    static func encode(aspectRatio: Double, intrinsicWidth: Double, caption: String?) -> String {
        let caption = caption ?? ""
        return "\(prefix)\(aspectRatio):\(intrinsicWidth):\(caption)"
    }

    static func parse(_ body: String) -> (aspectRatio: CGFloat, intrinsicWidth: CGFloat)? {
        guard body.hasPrefix(prefix) else { return nil }
        let fields = body.dropFirst(prefix.count).split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count >= 2,
              let ratio = Double(fields[0]),
              let width = Double(fields[1])
        else { return nil }
        return (CGFloat(ratio), CGFloat(width))
    }
}
