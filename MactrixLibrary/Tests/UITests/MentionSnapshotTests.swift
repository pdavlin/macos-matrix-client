import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-105 (D-6): the mention popup, and a composer with a chip.
///
/// The composer snapshot uses a TextKit 1 `NSTextView` with the same
/// attributed text the Mac composer builds (`ComposerAttributedText`), so it
/// shows the shipped chip cell. Same reference rules as
/// `ComposerAffordanceSnapshotTests`: fixed 2x scale, pinned appearance, and
/// skipped in CI.
@MainActor
struct MentionSnapshotTests {
    private let candidates = [
        MentionCandidate(userId: "@alice:example.org", displayName: "Alice Smith", avatarUrl: nil),
        MentionCandidate(userId: "@alfred:example.org", displayName: "Alfred Pennyworth", avatarUrl: nil),
        MentionCandidate(userId: "@slack_U02ABCDEF:example.org", displayName: "Alan (Slack)", avatarUrl: nil),
    ]

    private func assertPinnedSnapshot(of controller: NSViewController, testName: String = #function) {
        controller.view.appearance = NSAppearance(named: .aqua)
        assertSnapshot(of: controller, as: .scaledImage, testName: testName)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func suggestionPopup() {
        let list = MentionSuggestionList(
            suggestions: candidates,
            selectedIndex: 1,
            imageLoader: nil,
            onPick: { _ in }
        )
        .frame(width: 360)
        .background(Color.white)
        let controller = NSHostingController(rootView: list)
        controller.view.frame.size = controller.view.fittingSize
        assertPinnedSnapshot(of: controller)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func composerWithChip() {
        let segments: [ComposerSegment] = [
            .text("Thanks "),
            .mention(MentionTarget(userId: "@alice:example.org", displayName: "Alice Smith")),
            .text(" for the review!"),
        ]
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(x: 0, y: 0, width: 360, height: 10)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.backgroundColor = .white
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.black,
        ]
        textView.textStorage?.setAttributedString(
            ComposerAttributedText.attributedString(for: segments, attributes: attributes)
        )
        if let container = textView.textContainer, let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: container)
            let height = ceil(layoutManager.usedRect(for: container).height) + 2 * textView.textContainerInset.height
            textView.frame.size.height = height
        }

        let controller = NSViewController()
        controller.view = textView
        assertPinnedSnapshot(of: controller)
    }
}

/// The bridge between the composer's attributed text and its segments.
@MainActor
struct ComposerAttributedTextTests {
    private let alice = MentionTarget(userId: "@alice:example.org", displayName: "Alice")
    private let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]

    @Test func eachChipIsOneCharacter() {
        let attributed = ComposerAttributedText.attributedString(
            for: [.text("a "), .mention(alice), .mention(alice), .text(" b")],
            attributes: attributes
        )
        #expect(attributed.string == "a \u{FFFC}\u{FFFC} b")
    }

    @Test func segmentsRoundTrip() {
        let segments: [ComposerSegment] = [.text("a "), .mention(alice), .mention(alice), .text(" b")]
        let attributed = ComposerAttributedText.attributedString(for: segments, attributes: attributes)
        #expect(ComposerAttributedText.segments(from: attributed) == segments)
    }

    @Test func foreignAttachmentIsDropped() {
        let attributed = NSMutableAttributedString(string: "x")
        attributed.append(NSAttributedString(attachment: NSTextAttachment()))
        attributed.append(NSAttributedString(string: "y"))
        #expect(ComposerAttributedText.segments(from: attributed) == [.text("xy")])
    }

    @Test func chipCarriesTheMention() throws {
        let chip = ComposerAttributedText.chip(for: alice, attributes: attributes)
        let attachment = try #require(chip.attribute(.attachment, at: 0, effectiveRange: nil) as? MentionChipAttachment)
        #expect(attachment.mention == alice)
    }
}
