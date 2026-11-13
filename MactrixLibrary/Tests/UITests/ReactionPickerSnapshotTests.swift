import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots for the reaction picker popover (MATRIX-111, M2-B4).
///
/// The test renders the real picker content with the bundled emoji list,
/// a recent-emoji row, and a prepared query. The popover chrome is the
/// system's and is not part of the image.
@MainActor
struct ReactionPickerSnapshotTests {
    private let recents = ["😂", "🔥", "👀", "🙏", "🎉"]

    private func host(query: String) -> NSViewController {
        let picker = ReactionPickerView(catalog: .bundled, recents: recents, query: query) { _ in }
        let controller = NSHostingController(rootView: picker)
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance so the snapshot does not flip with light/dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    /// Recents on top, then "thumbs": 👍 and 👎, the first one selected, and
    /// its name on the bottom line.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func recentsAndASearchResult() {
        assertTextFieldSnapshot(of: host(query: "thumbs"), as: .scaledImage)
    }
}

/// MATRIX-155: the picker with the image pack of the chat's workspace. The
/// loader holds one solid-color square per URL in its cache, so the cells
/// draw without a network. Local gate only, as the other snapshots.
@MainActor
struct ReactionPickerImagePackSnapshotTests {
    /// Serves a solid-color square for each pack image, from the cache.
    private struct SquareLoader: ImageLoader {
        static let colors: [NSColor] = [.systemTeal, .systemOrange, .systemPurple, .systemGreen, .systemPink, .systemBlue]

        func cachedImage(matrixUrl: String) -> Image? {
            guard let number = matrixUrl.split(separator: "/").last.flatMap({ Int($0) }) else { return nil }
            let color = Self.colors[number % Self.colors.count]
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

    private static let shortcodes = [
        "acme", "blobwave", "cool-doge", "dancing_parrot", "fine", "lgtm", "meow_party", "nyan",
        "parrot_wave", "party_parrot", "shipit", "this-is-fine",
    ]

    private static let pack = ImagePack(
        key: "acme",
        displayName: "Acme emojis",
        emoji: shortcodes.enumerated().map { ImagePackEmoji(shortcode: $0.element, url: "mxc://example.org/\($0.offset)") }
    )

    private func host(query: String) -> NSViewController {
        let picker = ReactionPickerView(
            catalog: .bundled,
            recents: ["😂", "🔥", "mxc://example.org/3", "👀"],
            packs: [Self.pack],
            imageLoader: SquareLoader(),
            query: query
        ) { _ in }
        let controller = NSHostingController(rootView: picker)
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    /// Recents (without the custom key), then the "Acme emojis" section with
    /// twelve image cells, the first one selected, then the Unicode
    /// categories. The bottom line shows the image and its shortcode.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func packSectionBeforeTheUnicodeCategories() {
        assertTextFieldSnapshot(of: host(query: ""), as: .scaledImage)
    }

    /// "parrot": the Unicode parrot first, then the pack's three matches
    /// under the pack's title.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func searchFindsPackEmojiByShortcode() {
        assertTextFieldSnapshot(of: host(query: "parrot"), as: .scaledImage)
    }

    @Test func theRecentRowLeavesOutACustomKey() {
        let picker = ReactionPickerView(
            catalog: .bundled,
            recents: ["😂", "mxc://example.org/3", "😂", "", "👀"]
        ) { _ in }
        #expect(picker.recentRow.map(\.value) == ["😂", "👀"])
    }

    @Test func aPickOfAPackEmojiGivesItsImageURL() throws {
        var picked: [String] = []
        let picker = ReactionPickerView(
            catalog: EmojiCatalog(categories: []),
            recents: [],
            packs: [Self.pack],
            query: "shipit",
            onClose: {},
            onPick: { picked.append($0) }
        )
        let entry = try #require(picker.gridContent.entries.first)
        #expect(entry.name == "shipit")

        picker.pick(entry.value)

        #expect(picked == ["mxc://example.org/10"])
    }
}

/// The bundled emoji list that `scripts/generate-emoji-data.py` writes.
struct BundledEmojiCatalogTests {
    private let catalog = EmojiCatalog.bundled

    @Test func holdsTheNineUnicodeGroups() {
        #expect(catalog.categories.map(\.name) == [
            "Smileys & Emotion", "People & Body", "Animals & Nature", "Food & Drink",
            "Travel & Places", "Activities", "Objects", "Symbols", "Flags",
        ])
        #expect(catalog.entries.count == 1898)
    }

    @Test func holdsNoSkinToneVariants() {
        let skinTones: ClosedRange<UInt32> = 0x1F3FB ... 0x1F3FF
        let toned = catalog.entries.filter { entry in
            entry.value.unicodeScalars.contains { skinTones.contains($0.value) }
        }
        #expect(toned.isEmpty)
    }

    @Test func holdsEachEmojiOnce() {
        #expect(Set(catalog.entries.map(\.value)).count == catalog.entries.count)
    }

    @Test func thumbsFindsThumbsUpFirst() {
        #expect(catalog.search("thumbs").map(\.value).prefix(2) == ["👍", "👎"])
        #expect(catalog.search("THUMBS UP").first?.value == "👍")
        #expect(catalog.entry(for: "🎉")?.name == "party popper")
    }
}

/// MATRIX-138: the Mac timeline closes the picker through `onClose`, because
/// SwiftUI's `dismiss` has no presentation to end in an AppKit popover.
@MainActor
struct ReactionPickerCloseTests {
    @Test func aPickCallsOnPickThenOnClose() {
        var calls: [String] = []
        let picker = ReactionPickerView(
            catalog: EmojiCatalog(categories: []),
            recents: [],
            onClose: { calls.append("close") },
            onPick: { calls.append("pick \($0)") }
        )

        picker.pick("👍")

        #expect(calls == ["pick 👍", "close"])
    }

    @Test func closeCallsOnClose() {
        var closed = 0
        let picker = ReactionPickerView(
            catalog: EmojiCatalog(categories: []),
            recents: [],
            onClose: { closed += 1 },
            onPick: { _ in }
        )

        picker.close()

        #expect(closed == 1)
    }
}
