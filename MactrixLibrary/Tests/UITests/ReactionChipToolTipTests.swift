import AppKit
import Models
import SwiftUI
import Testing
@testable import UI

/// The reaction chip's tooltip in a hosted row (MATRIX-166): the chip puts
/// an AppKit view with `toolTip` over itself, and the view takes no click.
@MainActor
struct ReactionChipToolTipTests {
    private static let ownUserId = "@me:example.org"
    private static let names = ["@ana:example.org": "Ana", "@ben:example.org": "Ben"]

    private struct Sender: ReactionSenderData {
        let senderId: String
        let date = Date(timeIntervalSince1970: 0)
    }

    private struct ChipReaction: Reaction {
        let key: String
        let senders: [Sender]

        var id: String {
            key
        }

        init(key: String, senderIds: [String]) {
            self.key = key
            senders = senderIds.map { Sender(senderId: $0) }
        }
    }

    private func chip(_ reaction: ChipReaction) -> MessageReactionView<ChipReaction> {
        MessageReactionView(
            reaction: reaction,
            active: .constant(false),
            ownUserId: Self.ownUserId,
            displayName: { Self.names[$0] }
        )
    }

    /// Hosts `view` as the timeline hosts a row: an `NSHostingView` in a
    /// window that is not on screen.
    private func host(_ view: some View) -> (window: NSWindow, host: NSHostingView<AnyView>) {
        let host = NSHostingView(rootView: AnyView(view.padding(8)))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        window.contentView?.addSubview(host)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return (window, host)
    }

    private func toolTipViews(in view: NSView) -> [ReactionChipToolTipView] {
        view.subviews.flatMap { subview -> [ReactionChipToolTipView] in
            let own = (subview as? ReactionChipToolTipView).map { [$0] } ?? []
            return own + toolTipViews(in: subview)
        }
    }

    @Test func theHostedChipCarriesTheTooltipOverItsWholeFrame() throws {
        let reaction = ChipReaction(key: "👍", senderIds: ["@ana:example.org", "@ben:example.org", Self.ownUserId])
        let hosted = host(chip(reaction))
        defer { hosted.window.close() }

        let views = toolTipViews(in: hosted.host)
        #expect(views.count == 1)
        let toolTipView = try #require(views.first)
        #expect(toolTipView.toolTip == "Ana, Ben and You")

        // The tooltip view covers the chip: the host less its padding.
        let frame = toolTipView.convert(toolTipView.bounds, to: hosted.host)
        let chipFrame = hosted.host.bounds.insetBy(dx: 8, dy: 8)
        #expect(abs(frame.width - chipFrame.width) <= 1)
        #expect(abs(frame.height - chipFrame.height) <= 1)
    }

    @Test func theTooltipNamesACustomEmojiWhenTheNameIsKnown() {
        let reaction = ChipReaction(key: "mxc://example.org/parrot", senderIds: ["@ana:example.org", "@zed:example.org"])
        let named = host(
            chip(reaction).environment(\.reactionEmojiName) { url in url == "mxc://example.org/parrot" ? "partyparrot" : nil }
        )
        defer { named.window.close() }
        #expect(toolTipViews(in: named.host).first?.toolTip == ":partyparrot: · Ana and zed")

        let unnamed = host(chip(reaction))
        defer { unnamed.window.close() }
        #expect(toolTipViews(in: unnamed.host).first?.toolTip == "Ana and zed")
    }

    @Test func theAccessibilityLabelSaysTheSamePeople() {
        let reaction = ChipReaction(key: "👍", senderIds: ["@ana:example.org", "@ben:example.org", Self.ownUserId])
        #expect(chip(reaction).accessibilityText == "👍, 3 reactions: Ana, Ben and You")
        let image = ChipReaction(key: "mxc://example.org/parrot", senderIds: [Self.ownUserId])
        #expect(chip(image).accessibilityText == "custom emoji, 1 reaction: You")
    }

    /// A synthetic mouse event does not press a SwiftUI button in a window
    /// that is not on screen, with or without the tooltip view, so this
    /// test checks the two things that route the click: the AppKit hit test
    /// and the tooltip view's own answer. SwiftUI's side is
    /// `allowsHitTesting(false)` on the overlay.
    @Test func aClickOnTheChipGoesPastTheTooltipView() throws {
        let reaction = ChipReaction(key: "👍", senderIds: ["@ana:example.org", Self.ownUserId])
        let hosted = host(chip(reaction))
        defer { hosted.window.close() }

        let toolTipView = try #require(toolTipViews(in: hosted.host).first)
        let center = toolTipView.convert(CGPoint(x: toolTipView.bounds.midX, y: toolTipView.bounds.midY), to: nil)
        let parent = try #require(hosted.host.superview)

        // The hosting view takes the click, as it does for a chip with no
        // tooltip view, and gives it to the chip's button.
        #expect(hosted.host.hitTest(parent.convert(center, from: nil)) === hosted.host)
        let ownParent = try #require(toolTipView.superview)
        #expect(toolTipView.hitTest(ownParent.convert(center, from: nil)) == nil)
        #expect(!toolTipView.acceptsFirstResponder)
    }
}
