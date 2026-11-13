import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-154: a reaction whose key is an `mxc://` URI draws its image in
/// the chip, next to a Unicode chip. The loader is a stub, so the chips draw
/// without a network. Local gate only, as the other snapshots (contract R-8).
@MainActor
struct ReactionImageChipSnapshotTests {
    private nonisolated static let ownUserId = "@me:example.org"
    private nonisolated static let parrotKey = "mxc://example.org/parrot"
    private nonisolated static let shipKey = "mxc://example.org/ship"

    /// Serves a solid-color disc for each known URL, from the cache.
    private struct CachedLoader: ImageLoader {
        let colors: [String: NSColor]

        func cachedImage(matrixUrl: String) -> Image? {
            guard let color = colors[matrixUrl] else { return nil }
            let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
                color.setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
            return Image(nsImage: image)
        }

        func loadImage(matrixUrl: String, size _: CGSize?) async throws -> Image? {
            cachedImage(matrixUrl: matrixUrl)
        }
    }

    /// Has no cache, and its load does not end: the chip stays in the
    /// loading state.
    private struct PendingLoader: ImageLoader {
        func cachedImage(matrixUrl _: String) -> Image? {
            nil
        }

        func loadImage(matrixUrl _: String, size _: CGSize?) async throws -> Image? {
            try await Task.sleep(for: .seconds(3600))
            return nil
        }
    }

    private static let cached = CachedLoader(colors: [parrotKey: .systemGreen, shipKey: .systemPurple])

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

        init(key: String, count: Int, includesOwn: Bool) {
            self.key = key
            senders = (0 ..< count).map { index in
                Sender(senderId: includesOwn && index == 0 ? ReactionImageChipSnapshotTests.ownUserId : "@user\(index):example.org")
            }
        }

        var isOwn: Bool {
            senders.contains { $0.senderId == ReactionImageChipSnapshotTests.ownUserId }
        }
    }

    /// One Unicode chip, then an own image chip and another user's image chip.
    private static let mixed = [
        ChipReaction(key: "👍", count: 2, includesOwn: false),
        ChipReaction(key: parrotKey, count: 3, includesOwn: true),
        ChipReaction(key: shipKey, count: 1, includesOwn: false),
    ]

    private func strip(_ reactions: [ChipReaction], imageLoader: ImageLoader?) -> some View {
        HStack {
            ForEach(reactions) { reaction in
                MessageReactionView(reaction: reaction, active: .constant(reaction.isOwn), imageLoader: imageLoader)
            }
        }
    }

    private func snapshot(of view: some View) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: an unpinned snapshot flips with light/dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private func item(_ action: MessageAction) -> MessageActionItem {
        MessageActionItem(action: action, section: .respond, isEnabled: true)
    }

    private func fittingSize(_ reactions: [ChipReaction], imageLoader: ImageLoader?) -> CGSize {
        NSHostingController(rootView: strip(reactions, imageLoader: imageLoader)).view.fittingSize
    }

    /// The images draw in place of the `mxc://` text.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func imageReactionsLoaded() {
        assertSnapshot(of: snapshot(of: strip(Self.mixed, imageLoader: Self.cached)), as: .scaledImage)
    }

    /// While the load runs: a neutral square of the image's size.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func imageReactionsLoading() {
        assertSnapshot(of: snapshot(of: strip(Self.mixed, imageLoader: PendingLoader())), as: .scaledImage)
    }

    /// No image: the generic glyph, same size.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func imageReactionsNotLoaded() {
        assertSnapshot(of: snapshot(of: strip(Self.mixed, imageLoader: nil)), as: .scaledImage)
    }

    /// A custom emoji in the hover bar's quick reactions draws its image.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func hoverBarQuickReactionImage() {
        let items = [item(.toggleReaction(key: Self.parrotKey)), item(.toggleReaction(key: "👍")), item(.openReactionPicker)]
        let bar = HoverActionBarContent(items: items, perform: { _ in })
            .environment(\.timelineImageLoader, Self.cached)
        assertSnapshot(of: snapshot(of: bar), as: .scaledImage)
    }

    /// The row height is measured before the image loads, so the chip's size
    /// must not depend on the load, and an image chip must have the size of
    /// an emoji chip with the same tally.
    @Test
    func imageChipSizeDoesNotDependOnTheLoad() {
        let image = [ChipReaction(key: Self.parrotKey, count: 12, includesOwn: false)]
        let emoji = [ChipReaction(key: "👍", count: 12, includesOwn: false)]

        let loaded = fittingSize(image, imageLoader: Self.cached)
        #expect(loaded == fittingSize(image, imageLoader: PendingLoader()))
        #expect(loaded == fittingSize(image, imageLoader: nil))
        #expect(loaded == fittingSize(emoji, imageLoader: nil))
    }

    /// The hover bar's size comes from the tokens, not from a layout pass,
    /// so an image key must not change it.
    @Test
    func hoverBarSizeDoesNotDependOnTheKey() {
        let imageItems = [item(.toggleReaction(key: Self.parrotKey))]
        let emojiItems = [item(.toggleReaction(key: "👍"))]
        let imageBar = NSHostingController(rootView: HoverActionBarContent(items: imageItems, perform: { _ in }))
        let emojiBar = NSHostingController(rootView: HoverActionBarContent(items: emojiItems, perform: { _ in }))
        #expect(imageBar.view.fittingSize == emojiBar.view.fittingSize)
    }

    /// A menu title is text: an image key shows a name, not the URI.
    @Test
    func menuTitleOfAnImageKeyIsAName() {
        #expect(MessageActionPresentation.title(of: .toggleReaction(key: Self.parrotKey)) == "Custom Emoji")
        #expect(MessageActionPresentation.title(of: .toggleReaction(key: "👍")) != "Custom Emoji")
    }
}
