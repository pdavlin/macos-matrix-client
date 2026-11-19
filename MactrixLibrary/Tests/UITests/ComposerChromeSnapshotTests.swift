import AppKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-195: the composer field and its glass buttons, empty and typed,
/// light and dark, and the opaque Reduce Transparency fallback.
///
/// A text stands in for the app's `ChatTextView`. Glass renders flat in an
/// offscreen `NSHostingController`, and `cacheDisplay` draws nothing at all
/// for tinted glass, so the send capsule is untinted here
/// (`untintedForSnapshot`). The snapshots guard the layout (the field width,
/// the button row, the send symbol). The glass and the accent tint need a
/// look in the app (contract R-8).
@MainActor
struct ComposerChromeSnapshotTests {
    private func host(
        _ view: some View,
        appearance: NSAppearance.Name = .aqua
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .padding()
                    .frame(width: 420)
                    .background(Color(NSColor.windowBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not follow the system's.
        controller.view.appearance = NSAppearance(named: appearance)
        return controller
    }

    private func chrome(text: String?, isEditing: Bool = false, usesGlass: Bool = true) -> some View {
        ComposerChrome(
            hasContent: text != nil,
            canAttach: !isEditing,
            canPickEmoji: true,
            canSend: text != nil,
            isEditing: isEditing,
            usesGlass: usesGlass,
            actions: .init(attach: {}, emoji: {}, send: {})
        ) {
            Text(text ?? "Message Seth")
                .foregroundStyle(text == nil ? .secondary : .primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .untintedForSnapshot()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func emptyLight() {
        assertSnapshot(of: host(chrome(text: nil)), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func emptyDark() {
        assertSnapshot(of: host(chrome(text: nil), appearance: .darkAqua), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func typedLight() {
        assertSnapshot(of: host(chrome(text: "Lunch at noon?")), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func typedDark() {
        assertSnapshot(of: host(chrome(text: "Lunch at noon?"), appearance: .darkAqua), as: .scaledImage)
    }

    /// Edit mode: the attach button is disabled and send shows a checkmark.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func editingLight() {
        assertSnapshot(of: host(chrome(text: "Lunch at one?", isEditing: true)), as: .scaledImage)
    }

    /// Reduce Transparency: an opaque field and plain buttons, no glass.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func opaqueTypedLight() {
        assertSnapshot(of: host(chrome(text: "Lunch at noon?", usesGlass: false)), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func opaqueTypedDark() {
        assertSnapshot(of: host(chrome(text: "Lunch at noon?", usesGlass: false), appearance: .darkAqua), as: .scaledImage)
    }
}
