import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
import Tokens
@testable import UI

/// A message with the fields the row header reads.
private struct JumboEvent: Models.EventTimelineItem {
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

/// The two appearances every jumbo case is recorded in.
enum JumboSnapshotAppearance: String, CaseIterable, Sendable {
    case light
    case dark

    var name: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

/// MATRIX-137: emoji-only text messages draw at `jumboEmojiSize`.
///
/// Each image is one full message row, composed the way the app's
/// `ChatMessageView` composes it: `MessageRunRow` with the profile header,
/// `MessageEventBodyView`, and inside it the reply preview (with its 10pt
/// bottom padding) above the body. The body picks its view the way the app's
/// `FormattedBodyView` does for a plain-text body: `JumboEmojiText` when
/// `JumboEmoji.jumboText` returns text, else a body-size `Text`.
///
/// Snapshot references render at a fixed 2x through `.scaledImage` (S-26).
@MainActor
struct JumboEmojiSnapshotTests {
    private static let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"

    /// The body view the app draws for a plain-text body.
    @ViewBuilder
    private func messageBody(_ body: String) -> some View {
        if let jumboText = JumboEmoji.jumboText(body: body, formattedBody: nil) {
            JumboEmojiText(jumboText)
        } else {
            Text(verbatim: body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ body: String, replyTo reply: (name: String, text: String)? = nil) -> some View {
        let event = JumboEvent()
        return MessageRunRow(grouping: .standalone) {
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
                VStack(alignment: .leading, spacing: 10) {
                    if let reply {
                        MessageReplyView(username: reply.name, message: reply.text)
                            .padding(.bottom, 10)
                    }
                    messageBody(body)
                }
            }
        }
        .font(.system(size: CGFloat(TypographyToken.defaultBaseFontSize)))
    }

    private func snapshot(
        of view: some View,
        appearance: NSAppearance.Name,
        width: CGFloat = 420
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: an unpinned snapshot flips with light/dark mode
        // and fails by time of day.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    /// One reference per appearance, named for it, so the parameterized
    /// test never leans on the per-test snapshot counter.
    private func assertRow(
        _ view: some View,
        appearance: JumboSnapshotAppearance,
        testName: String = #function
    ) {
        assertSnapshot(
            of: snapshot(of: view, appearance: appearance.name),
            as: .scaledImage,
            named: appearance.rawValue,
            testName: testName
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: JumboSnapshotAppearance.allCases)
    func oneEmoji(appearance: JumboSnapshotAppearance) {
        assertRow(row("\u{1F44D}"), appearance: appearance)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: JumboSnapshotAppearance.allCases)
    func threeEmoji(appearance: JumboSnapshotAppearance) {
        assertRow(row("\u{1F389}\u{1F44D}\u{1F3FD}\u{2764}\u{FE0F}"), appearance: appearance)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: JumboSnapshotAppearance.allCases)
    func zwjFamily(appearance: JumboSnapshotAppearance) {
        assertRow(row(Self.family), appearance: appearance)
    }

    /// A reply still qualifies: only the body decides.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: JumboSnapshotAppearance.allCases)
    func jumboReply(appearance: JumboSnapshotAppearance) {
        assertRow(
            row("\u{1F602}\u{1F602}", replyTo: (name: "Bob Kahn", text: "The build is green on the first try.")),
            appearance: appearance
        )
    }

    /// The control: an emoji next to text stays at body size.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: JumboSnapshotAppearance.allCases)
    func textWithEmojiIsNotJumbo(appearance: JumboSnapshotAppearance) {
        assertRow(row("ok \u{1F44D}"), appearance: appearance)
    }

    /// The measured height of a jumbo row is larger than the same row at body
    /// size. The table measures rows with the view it draws, so this checks
    /// that the 40pt line reaches the fitting size the measurement reads.
    @Test
    func jumboRowMeasuresTallerThanTextRow() {
        let jumboHeight = snapshot(of: row("\u{1F44D}"), appearance: .aqua).view.fittingSize.height
        let textHeight = snapshot(of: row("ok \u{1F44D}"), appearance: .aqua).view.fittingSize.height
        #expect(jumboHeight > textHeight)
        #expect(jumboHeight - textHeight >= TypographyToken.jumboEmojiSize - CGFloat(TypographyToken.defaultBaseFontSize))
    }
}
