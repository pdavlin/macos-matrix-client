import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-148: the account icon as the avatar badge, on a plain row and on a
/// merged row. The loader holds one solid-color icon per URL in its cache, so
/// the badges draw without a network. Local gate only, as the other
/// snapshots (contract R-8).
@MainActor
struct AccountBadgeSnapshotTests {
    /// Serves a solid-color square for each known URL, from the cache.
    private struct IconLoader: ImageLoader {
        let colors: [String: NSColor]

        func cachedImage(matrixUrl: String) -> Image? {
            guard let color = colors[matrixUrl] else { return nil }
            let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
                color.setFill()
                rect.fill()
                return true
            }
            return Image(nsImage: image)
        }

        func loadImage(matrixUrl: String, size _: CGSize?) async throws -> Image? {
            cachedImage(matrixUrl: matrixUrl)
        }
    }

    private static let loader = IconLoader(colors: ["mxc://a/dev": .systemTeal, "mxc://a/pizza": .systemOrange])

    private func row(_ model: ChatListRowModel) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                ChatListRow(model: model, imageLoader: Self.loader)
                    .frame(width: 320)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private func member(_ id: String, account: ChatAccount?) -> ChatListRowModel {
        var model = ChatListRowModel(
            id: id, title: "Seth Redacted", isDirect: true, preview: "Pizza at six?", timestamp: "3:42 PM", network: .slack
        )
        model.account = account
        return model
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func plainRowWithAccountIcon() {
        let model = member("!a", account: ChatAccount(name: "DevObsessed", avatarUrl: "mxc://a/dev"))
        assertSnapshot(of: row(model), as: .scaledImage)
    }

    /// An account without an icon keeps the network letter.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func plainRowWithoutAccountIcon() {
        assertSnapshot(of: row(member("!a", account: ChatAccount(name: "DevObsessed"))), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func mergedRowWithTwoAccountIcons() throws {
        let members = [
            member("!a", account: ChatAccount(name: "DevObsessed", avatarUrl: "mxc://a/dev")),
            member("!b", account: ChatAccount(name: "pizza box audit committee", avatarUrl: "mxc://a/pizza")),
        ]
        let merge = MergedChat(id: "m", name: "Seth Redacted", rooms: ["!a", "!b"])
        let merged = try #require(ChatListMerging.entry(for: merge, members: members.map { ChatListEntry(row: $0) }))
        assertSnapshot(of: row(merged.row), as: .scaledImage)
    }
}
