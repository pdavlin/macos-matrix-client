import AppKit
import MessageFormatting
import Models
import SnapshotTesting
import SwiftUI
import Testing
import Tokens
@testable import UI

/// A message with the fields the row header reads.
private struct EmoticonEvent: Models.EventTimelineItem {
    var isRemote: Bool { true }
    var sender: String { "@ada:example.org" }
    var senderProfileDetails: ProfileDetails {
        .ready(displayName: "Ada Lovelace", displayNameAmbiguous: false, avatarUrl: nil)
    }

    var isOwn: Bool { false }
    var isEditable: Bool { false }
    var date: Date {
        let components = DateComponents(year: 2026, month: 10, day: 23, hour: 9, minute: 0)
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

/// MATRIX-153: a custom emoticon in a message body.
///
/// Each image is one full message row, composed the way the app's
/// `ChatMessageView` composes it, with `FormattedBodyText` as the body. The
/// loader serves a solid-color square from its cache, so nothing loads.
///
/// Snapshot references render at a fixed 2x through `.scaledImage` (S-26).
@MainActor
struct BodyEmoticonSnapshotTests {
    private static let parrot = "mxc://example.org/parrot"
    private static let shipIt = "mxc://example.org/shipit"

    private static func emoticon(_ source: String, _ name: String) -> String {
        "<img data-mx-emoticon src=\"\(source)\" alt=\":\(name):\" title=\":\(name):\" height=\"32\"/>"
    }

    private static let html = "The deploy is done \(emoticon(parrot, "partyparrot")) and the review is in "
        + "\(emoticon(shipIt, "ok")), so <strong>merge it</strong> before the freeze starts on Friday."

    private static let loaded = EmoticonStubLoader(colors: [parrot: .systemGreen, shipIt: .systemOrange])

    private func row(_ html: String, loader: EmoticonStubLoader) -> NSHostingController<AnyView> {
        let event = EmoticonEvent()
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
                    html: html,
                    baseFontSize: CGFloat(TypographyToken.defaultBaseFontSize),
                    imageLoader: loader
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
    func rowWithLoadedEmoticons() {
        assertSnapshot(of: row(Self.html, loader: Self.loaded), as: .scaledImage)
    }

    /// The cache holds no image: each square draws its alt text.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func rowWithAltText() {
        assertSnapshot(of: row(Self.html, loader: EmoticonStubLoader()), as: .scaledImage)
    }

    /// A body of only emoticons draws at body size, not jumbo.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func rowOfOnlyEmoticons() {
        let html = Self.emoticon(Self.parrot, "partyparrot") + Self.emoticon(Self.shipIt, "ok")
        assertSnapshot(of: row(html, loader: Self.loaded), as: .scaledImage)
    }

    /// The row is the same size with the alt text and with the images.
    @Test func rowSizeDoesNotDependOnTheImages() {
        let pending = row(Self.html, loader: EmoticonStubLoader()).view.fittingSize
        let loaded = row(Self.html, loader: Self.loaded).view.fittingSize
        #expect(pending == loaded)
        #expect(pending.height > 0)
    }
}
