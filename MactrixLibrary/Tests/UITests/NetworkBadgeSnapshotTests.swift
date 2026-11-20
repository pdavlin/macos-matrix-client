import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-194: the letter-circle network badge with its cut-out ring, in
/// light and dark mode, and the setting that hides it.
///
/// No image loader, so every avatar is its colored initials. References
/// render at a fixed 2x through `.scaledImage`; snapshots are the
/// local/agent-side gate (contract R-8).
@MainActor
struct NetworkBadgeSnapshotTests {
    private func snapshot(
        of view: some View,
        width: CGFloat,
        appearance: NSAppearance.Name
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance: an unpinned snapshot flips with light/dark mode.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    /// Asserts `view` against a light and a dark reference.
    private func assertBothAppearances(
        of view: some View,
        width: CGFloat,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            assertSnapshot(
                of: snapshot(of: view, width: width, appearance: appearance),
                as: .scaledImage,
                named: name,
                fileID: fileID,
                file: filePath,
                testName: testName,
                line: line,
                column: column
            )
        }
    }

    private let slackModel = ChatListRowModel(
        id: "!slack:example.org",
        title: "Design review",
        preview: "Dana: Pushed the new mocks to the shared folder",
        timestamp: "9:41 AM",
        network: .slack
    )

    private let nativeModel = ChatListRowModel(
        id: "!native:example.org",
        title: "Matrix HQ",
        preview: "Erin: The homeserver upgrade is done",
        timestamp: "Tue"
    )

    private var mergedModel: ChatListRowModel {
        var model = ChatListRowModel(
            id: "merged:family",
            title: "Family",
            preview: "Mom: Dinner at six?",
            timestamp: "Mon",
            network: .slack
        )
        model.memberBadges = [
            ChatBadge(network: .slack),
            ChatBadge(network: .googleChat),
            ChatBadge(network: .groupMe),
        ]
        return model
    }

    private var pinnedModel: ChatListRowModel {
        ChatListRowModel(
            id: "!pinned:example.org",
            title: "Sam Lee",
            isDirect: true,
            unread: ChatListUnread(count: 2, isUnread: true),
            network: .googleChat,
            heroes: [ChatListHero(userId: "@googlechat_1:example.org", displayName: "Sam Lee")]
        )
    }

    // MARK: Snapshots

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func slackRow() {
        assertBothAppearances(of: ChatListRow(model: slackModel, imageLoader: nil), width: 320)
    }

    /// A native Matrix chat has no badge and no cut-out.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func nativeRow() {
        assertBothAppearances(of: ChatListRow(model: nativeModel, imageLoader: nil), width: 320)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func pinnedTileWithBadge() {
        let tile = PinnedChatTile(model: pinnedModel, isSelected: false, imageLoader: nil, action: {})
        assertBothAppearances(of: tile, width: 96)
    }

    /// A merged chat keeps its MATRIX-141 stack: each badge cuts its ring
    /// into the avatar and into the badges behind it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func mergedRow() {
        assertBothAppearances(of: ChatListRow(model: mergedModel, imageLoader: nil), width: 320)
    }

    // MARK: Setting

    @Test
    func settingOffHidesTheBadges() {
        #expect(ChatListAvatar.visibleBadges(of: slackModel, showsNetworkBadges: true).count == 1)
        #expect(ChatListAvatar.visibleBadges(of: mergedModel, showsNetworkBadges: true).count == 3)
        #expect(ChatListAvatar.visibleBadges(of: slackModel, showsNetworkBadges: false).isEmpty)
        #expect(ChatListAvatar.visibleBadges(of: mergedModel, showsNetworkBadges: false).isEmpty)
    }

    /// With the setting off, a Slack avatar draws the same pixels as the
    /// same chat with no network: no badge and no cut-out ring.
    @Test
    func settingOffDrawsTheAvatarWithoutBadge() throws {
        var native = slackModel
        native.network = nil
        let hidden = try #require(pixels(of: ChatListAvatar(model: slackModel, size: 36, imageLoader: nil)
                .environment(\.showsNetworkBadges, false)))
        let plain = try #require(pixels(of: ChatListAvatar(model: native, size: 36, imageLoader: nil)))
        let shown = try #require(pixels(of: ChatListAvatar(model: slackModel, size: 36, imageLoader: nil)))
        #expect(isSameDrawing(hidden, plain))
        #expect(!isSameDrawing(shown, plain))
    }

    /// The same pixels, give or take one level per byte (MATRIX-218).
    ///
    /// After SwiftUI has drawn the same avatar three times in the process,
    /// it draws the gradient one level apart in some pixels. The other tests
    /// draw this avatar too, so, in a parallel run, that change could come
    /// between two renders of this test, and exact equality failed at
    /// random. A badge or its cut-out ring changes pixels by much more than
    /// one level.
    private func isSameDrawing(_ first: Data, _ second: Data) -> Bool {
        first.count == second.count && zip(first, second).allSatisfy { abs(Int($0) - Int($1)) <= 1 }
    }

    private func pixels(of view: some View) -> Data? {
        let renderer = ImageRenderer(content: view.padding(4).environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { return nil }
        return data as Data
    }

    // MARK: Cut-out ring

    /// The alpha of one pixel of `view` rendered at 1x on a clear background.
    private func alpha(of view: some View, x: Int, y: Int) -> UInt8? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // Move the wanted pixel onto the 1x1 context. CG's origin is
            // bottom-left.
            context.draw(
                image,
                in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height)
            )
            return true
        }
        return drawn ? pixel[3] : nil
    }

    /// A pixel between the badge and the avatar is opaque avatar without a
    /// badge, and transparent with one: the ring is cut out.
    @Test
    func ringCutsThroughTheAvatar() throws {
        // On a 36 pt avatar the 13.5 pt badge is centered 31.5 pt from the
        // top-left, and its 1.62 pt ring spans 6.75...8.37 pt from that
        // center. (26, 26) is 7.8 pt from the badge center, and 11.3 pt from
        // the avatar's center, inside its 18 pt radius.
        var native = slackModel
        native.network = nil
        let withBadge = try #require(alpha(of: ChatListAvatar(model: slackModel, size: 36, imageLoader: nil), x: 26, y: 26))
        let without = try #require(alpha(of: ChatListAvatar(model: native, size: 36, imageLoader: nil), x: 26, y: 26))
        #expect(without == 255)
        // Not exactly 0: the ring's anti-aliased edge is near this pixel.
        #expect(withBadge < 16)
    }

    // MARK: Glyph mapping

    /// Every default glyph is a system symbol on this OS.
    @Test(arguments: ChatListNetwork.allCases)
    func badgeSymbolExists(network: ChatListNetwork) {
        #expect(NSImage(systemSymbolName: network.badgeSymbolName, accessibilityDescription: nil) != nil)
    }

    /// Networks that share a letter differ by tint, so no two badges look
    /// the same.
    @Test
    func everyNetworkHasADistinctBadge() {
        let looks = ChatListNetwork.allCases.map { "\($0.badgeSymbolName) \($0.badgeTint.light)" }
        #expect(Set(looks).count == ChatListNetwork.allCases.count)
    }
}
