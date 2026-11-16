import AppKit
import ObjectiveC
import SnapshotTesting
import Testing

/// Keeps SwiftUI's text-field line-height cache correct for the life of the
/// test process (MATRIX-120, MATRIX-126, MATRIX-158).
///
/// The fault. On macOS, SwiftUI gives a `TextField` its height from
/// `NSFont.lineHeight`, an internal SwiftUI property. The call path is
/// `PlatformTextFieldAdaptor.updateNSView` → `VerticalTextField.updateLimits`
/// → `InlineCache.get` → `NSFont.lineHeight` →
/// `-[NSLayoutManager defaultLineHeightForFont:]`. The `InlineCache` is shared
/// by all views in the process, it holds 3 entries, and its key is the address
/// of the font object. It does not retain the font. The font that SwiftUI
/// measures is a short-lived object, not the font that stays on the
/// `NSTextField`. When that object is released, a later font of a different
/// size can get the same address. Then the cache returns the line height of
/// the released font: a 17 pt field gets the 16 pt height of a 13 pt field,
/// or a 13 pt field gets 18 pt or 20 pt. The `NSTextField` has the correct
/// font, so its intrinsic size is correct and no relayout changes the frame.
/// Whether an address is used again depends on the allocator, so the fault
/// occurred at random: in about 1 of 8 runs of the full suite.
///
/// The cure. Each cache miss calls `defaultLineHeightForFont:`. The guard
/// replaces that method with one that retains its font and then calls the
/// original implementation. A retained font is never released, so no other
/// font can get its address, and no cache entry can become stale. The cost is
/// a small number of font objects that stay alive until the test process
/// ends.
///
/// The guard must be in place before the first layout of a SwiftUI text
/// field in the process. `assertTextFieldSnapshot` installs it before it
/// makes the view, so every test that shows a text field must use that
/// function. `TextFieldLineHeightTests` is the reproducer for the fault.
@MainActor
enum TextFieldLineHeightGuard {
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        let selector = #selector(NSLayoutManager.defaultLineHeight(for:))
        guard let method = class_getInstanceMethod(NSLayoutManager.self, selector) else {
            Issue.record("MATRIX-158: NSLayoutManager has no defaultLineHeight(for:), so the guard is not installed")
            return
        }
        typealias LineHeightFunction = @convention(c) (NSLayoutManager, Selector, NSFont) -> CGFloat
        let original = unsafeBitCast(method_getImplementation(method), to: LineHeightFunction.self)
        let replacement: @convention(block) (NSLayoutManager, NSFont) -> CGFloat = { manager, font in
            // Not balanced on purpose: the font must stay alive.
            _ = Unmanaged.passRetained(font)
            return original(manager, selector, font)
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
}

/// Asserts a snapshot of a view that shows a SwiftUI text field.
///
/// It installs `TextFieldLineHeightGuard` and then calls `assertSnapshot`
/// with the same arguments. There is one attempt and no retry. Use it in
/// every test that shows a text field: a text field that is laid out before
/// the guard is in place can put a stale entry into SwiftUI's cache.
///
/// `value` is an autoclosure because some hosts do a layout pass when they
/// make the view. The guard must be in place before that pass.
@MainActor
func assertTextFieldSnapshot<Value>(
    of value: @autoclosure () -> Value,
    as snapshotting: Snapshotting<Value, some Any>,
    named name: String? = nil,
    record: SnapshotTestingConfiguration.Record? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    TextFieldLineHeightGuard.install()
    assertSnapshot(
        of: value(),
        as: snapshotting,
        named: name,
        record: record,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
}
