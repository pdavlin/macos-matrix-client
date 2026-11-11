import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
import Tokens
@testable import UI

/// MATRIX-145: the hover action bar as a standalone view, the view the Mac
/// timeline's floating bar hosts.
///
/// Each image is the end state of the reveal motion (MATRIX-135), so the bar
/// is drawn without it. The quick reactions show at rest: monochrome and
/// dimmed. The hover color of a button needs a pointer and is not shown.
@MainActor
struct HoverActionBarSnapshotTests {
    /// An own text message: every hover button it can have.
    private static let subject = MessageActionSubject(
        content: .text,
        isOwn: true,
        eventId: "$event:example.org",
        canBeRepliedTo: true,
        isPinned: false,
        copyableText: "Hello",
        isEditable: true
    )

    private static var itemsWithReactions: [MessageActionItem] {
        MessageActionModel.items(for: subject, on: .hoverRow)
    }

    /// The bar without its quick reactions, and so without the divider.
    private static var itemsWithoutReactions: [MessageActionItem] {
        itemsWithReactions.filter { !$0.action.isQuickReaction }
    }

    private func snapshot(
        of items: [MessageActionItem],
        appearance: NSAppearance.Name = .aqua
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                HoverActionBarContent(items: items, perform: { _ in })
                    .padding(12)
                    .background(Color(NSColor.windowBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: an unpinned snapshot flips with light/dark mode.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func withQuickReactionsLight() {
        assertSnapshot(of: snapshot(of: Self.itemsWithReactions), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func withQuickReactionsDark() {
        assertSnapshot(of: snapshot(of: Self.itemsWithReactions, appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func withoutQuickReactionsLight() {
        assertSnapshot(of: snapshot(of: Self.itemsWithoutReactions), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func withoutQuickReactionsDark() {
        assertSnapshot(of: snapshot(of: Self.itemsWithoutReactions, appearance: .darkAqua), as: .scaledImage)
    }

    // MARK: - Layout facts the floating bar's placement reads

    /// The floating bar's host is sized from `HoverActionBarGeometry.barSize`,
    /// not by layout. The token size must be the laid-out size.
    @Test func theTokenSizeIsTheLaidOutSize() {
        let reactionsOnly = Self.itemsWithReactions.filter(\.action.isQuickReaction)
        for items in [Self.itemsWithReactions, Self.itemsWithoutReactions, reactionsOnly] {
            let host = NSHostingView(rootView: HoverActionBarContent(items: items, perform: { _ in }))
            #expect(host.fittingSize == HoverActionBarGeometry.barSize(for: items))
        }
    }

    /// `HoverActionBarGeometry.bodyTopInset(for:)` takes the profile header
    /// to be as tall as its avatar. That holds while the bold name is
    /// shorter than the avatar at every font size the settings allow.
    @Test(arguments: [TypographyToken.minBaseFontSize, TypographyToken.defaultBaseFontSize, TypographyToken.maxBaseFontSize])
    func theProfileHeaderIsAsTallAsItsAvatar(fontSize: Int) {
        let header = MessageEventProfileView(event: MockEventTimelineItem(), actions: MockMessageEventActions(), imageLoader: nil)
            .font(.system(size: CGFloat(fontSize)))
            .frame(width: 420)
        let host = NSHostingView(rootView: header)
        #expect(host.fittingSize.height == DensityToken.profileAvatarSize)
    }
}
