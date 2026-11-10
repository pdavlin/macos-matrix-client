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
        assertSnapshot(of: host(query: "thumbs"), as: .scaledImage)
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
