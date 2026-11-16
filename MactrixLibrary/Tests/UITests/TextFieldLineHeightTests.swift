import AppKit
import SwiftUI
import Testing

/// The reproducer for the text-field line-height fault (MATRIX-158), and the
/// check that `TextFieldLineHeightGuard` cures it.
///
/// The test makes many plain text fields, one after the other, in three font
/// sizes, and releases each one. Without the guard, some field gets the line
/// height of a different font size in a part of the runs: SwiftUI's cache
/// finds a released font at the address of the new font. To see the fault,
/// run this suite alone with the guard off:
///
///     MATRIX158_NO_GUARD=1 swift test --package-path MactrixLibrary --filter TextFieldLineHeightTests
@MainActor
struct TextFieldLineHeightTests {
    private static let fontSizes: [CGFloat] = [13, 15, 17]
    private static let fieldCount = 240

    private func firstEditableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        for subview in view.subviews {
            if let field = firstEditableField(in: subview) {
                return field
            }
        }
        return nil
    }

    /// The height of the field after layout, and the line height of its font.
    ///
    /// The labels use fonts that change with `index`. They make SwiftUI
    /// release the fonts of earlier views, as the labels of a real screen do.
    private func measure(fontSize: CGFloat, index: Int) -> (height: CGFloat, lineHeight: CGFloat)? {
        let content = VStack(alignment: .leading) {
            TextField("Placeholder", text: .constant("abc"))
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
            ForEach(0 ..< 6) { label in
                Text("Label")
                    .font(.system(size: CGFloat(9 + (index * 7 + label * 5) % 23), weight: label % 2 == 0 ? .regular : .semibold))
            }
        }
        .frame(width: 200)
        let host = NSHostingView(rootView: content)
        host.frame.size = host.fittingSize
        _ = ScaledImageSnapshotting.render(host, scale: 1)
        guard let textField = firstEditableField(in: host), let font = textField.font else { return nil }
        return (textField.frame.height, NSLayoutManager().defaultLineHeight(for: font))
    }

    @Test func aPlainFieldGetsTheLineHeightOfItsOwnFont() {
        if ProcessInfo.processInfo.environment["MATRIX158_NO_GUARD"] == nil {
            TextFieldLineHeightGuard.install()
        }
        // A fixed sequence with no period of 3, so each size follows each
        // other size.
        var state: UInt64 = 158
        var wrong: [String] = []
        for index in 0 ..< Self.fieldCount {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let fontSize = Self.fontSizes[Int((state >> 33) % UInt64(Self.fontSizes.count))]
            // The pool releases the view, and the fonts that only the view
            // holds, before the next view is made.
            let measured = autoreleasepool { measure(fontSize: fontSize, index: index) }
            guard let measured else {
                Issue.record("Field \(index) (\(fontSize) pt) has no NSTextField after layout")
                return
            }
            if measured.height != measured.lineHeight {
                wrong.append("field \(index): \(fontSize) pt, height \(measured.height), line height \(measured.lineHeight)")
            }
        }
        #expect(wrong.isEmpty, "Fields with the line height of a different font: \(wrong.prefix(5))")
    }
}
