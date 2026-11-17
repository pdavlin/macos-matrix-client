import AppKit
import MessageFormatting
import Models
import SnapshotTesting
import SwiftUI
import Testing
import Tokens
@testable import UI

/// A message with the fields the row header reads.
private struct MusicLinkEvent: Models.EventTimelineItem {
    var isRemote: Bool { true }
    var sender: String { "@ada:example.org" }
    var senderProfileDetails: ProfileDetails {
        .ready(displayName: "Ada Lovelace", displayNameAmbiguous: false, avatarUrl: nil)
    }

    var isOwn: Bool { false }
    var isEditable: Bool { false }
    var date: Date {
        let components = DateComponents(year: 2026, month: 11, day: 17, hour: 9, minute: 0)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    var sendState: LocalSendState? { nil }
    var localCreatedAt: UInt64? { nil }
    var userReadReceipts: [String: Receipt] { [:] }
    var canBeRepliedTo: Bool { true }
    var userId: String { sender }
    var displayName: String? { "Ada Lovelace" }
    var avatarUrl: String? { nil }
}

/// MATRIX-178: a message row with a marked music link, composed the way
/// the app's `ChatMessageView` composes it, with `FormattedBodyText` as the
/// body.
///
/// The marker glyph is the SF Symbol `music.note`, and the OS owns its
/// shape: macOS 27.3 (26C5035r) draws it differently from the OS before it
/// (MATRIX-176, `LabelSnapshotTests.pickerContent`). The precision 0.9995
/// lets one changed glyph pass, and a layout or color change fail.
///
/// Snapshot references render at a fixed 2x through `.scaledImage` (S-26).
@MainActor
struct MusicLinkSnapshotTests {
    private static let html = #"<p>This one is great: <a href="https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=0123456789abcdef">"#
        + #"https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=0123456789abcdef</a>, the whole "#
        + #"<a href="https://open.spotify.com/intl-de/album/1A2GTWGtFfWp7KSQTwWOyo">album</a> too. "#
        + #"My <a href="https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M">playlist</a> and "#
        + #"<a href="https://example.org">a site</a> stay plain.</p>"#

    private func row(marksMusicLinks: Bool) -> NSHostingController<AnyView> {
        let event = MusicLinkEvent()
        let view = MessageRunRow(grouping: .standalone) {
            MessageEventProfileView(event: event, actions: MockMessageEventActions(), imageLoader: nil)
        } message: {
            MessageEventBodyView(
                event: event,
                focused: false,
                reactions: [MockReaction](),
                actions: MockMessageEventActions(),
                ownUserID: "@patrick:example.org",
                imageLoader: nil,
                roomMembers: [MockRoomMember]()
            ) {
                FormattedBodyText(
                    html: Self.html,
                    baseFontSize: CGFloat(TypographyToken.defaultBaseFontSize),
                    imageLoader: nil,
                    marksMusicLinks: marksMusicLinks
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: CGFloat(TypographyToken.defaultBaseFontSize)))

        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: 420)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func rowWithMarkedMusicLinks() {
        assertSnapshot(of: row(marksMusicLinks: true), as: .scaledImage(precision: 0.9995))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func rowWithTheSwitchOff() {
        assertSnapshot(of: row(marksMusicLinks: false), as: .scaledImage(precision: 0.9995))
    }
}
