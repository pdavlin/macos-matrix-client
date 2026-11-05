import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots of the forward confirmation (MATRIX-112, M2-B5).
///
/// They check that the room name, the preview, and the media size fit, that
/// Cancel is the default (prominent) button, and the sending state. The
/// sheet has no text field. The spinner uses the static stand-in, because an
/// AppKit progress control has no stable frame.
@MainActor
struct MessageForwardSheetSnapshotTests {
    private func host(_ view: some View) -> NSViewController {
        let controller = NSHostingController(
            rootView: view.environment(\.usesStaticProgressIndicators, true)
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not flip with dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private static let enUS = Locale(identifier: "en_US")

    private func sheet(_ content: MessageForwardContent, roomName: String? = "Alice", isSending: Bool = false) -> some View {
        MessageForwardSheet(content: content, roomName: roomName, isSending: isSending, onForward: {}, onCancel: {})
            .environment(\.locale, Self.enUS)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func textWithMention() {
        let body = "Lunch at noon? [Bob](https://matrix.to/#/@bob:example.org) is in."
        assertSnapshot(of: host(sheet(.text(body: body))), as: .scaledImage)
    }

    /// The case from the story: "Forward 24.3 MB video to Alice?".
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func videoWithSizeAndCaption() {
        let video = MessageForwardMedia(kind: .video, filename: "launch.mov", caption: "From the launch", byteCount: 24_300_000)
        assertSnapshot(of: host(sheet(.media(video))), as: .scaledImage)
    }

    /// An image with no size in its event and no caption.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func imageWithoutSize() {
        let image = MessageForwardMedia(kind: .image, filename: "IMG_0042.jpg", caption: nil, byteCount: nil)
        assertSnapshot(of: host(sheet(.media(image), roomName: "Design Team")), as: .scaledImage)
    }

    /// After Forward: a spinner, and both buttons disabled.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func sending() {
        let file = MessageForwardMedia(kind: .file, filename: "report.pdf", caption: nil, byteCount: 1_200_000)
        assertSnapshot(of: host(sheet(.media(file), isSending: true)), as: .scaledImage)
    }
}
