import AppKit
@testable import MessageFormatting
import Testing

/// MATRIX-201: which link clicks of a body go to the post peek. A plain left
/// click in the field's window does. ⌘-click and the other modifiers, and a
/// click outside the window (the context menu's Open Link), open the link
/// as before.
@MainActor
struct LinkClickHandlerTests {
    private func click(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = [], in window: NSWindow?) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    private func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func aLinkValueIsAURLOrAString() {
        #expect(LinkCursorTextField.url(of: URL(string: "https://x.com/jack/status/20") as Any)?.absoluteString == "https://x.com/jack/status/20")
        #expect(LinkCursorTextField.url(of: "https://bsky.app/profile/a/post/b")?.absoluteString == "https://bsky.app/profile/a/post/b")
        #expect(LinkCursorTextField.url(of: 42) == nil)
    }

    @Test func modifiersAndOtherWindowsOpenTheBrowser() throws {
        let window = window()
        let other = self.window()
        for flags: NSEvent.ModifierFlags in [.command, .option, .shift, .control] {
            let event = try #require(click(.leftMouseUp, flags: flags, in: window))
            #expect(!LinkCursorTextField.isPlainClick(event, in: window))
        }
        let elsewhere = try #require(click(.leftMouseUp, in: other))
        #expect(!LinkCursorTextField.isPlainClick(elsewhere, in: window))
        let rightClick = try #require(click(.rightMouseUp, in: window))
        #expect(!LinkCursorTextField.isPlainClick(rightClick, in: window))
        let noWindow = try #require(click(.leftMouseUp, in: nil))
        #expect(!LinkCursorTextField.isPlainClick(noWindow, in: nil))
    }

    @Test func aPlainClickInTheWindowPeeks() throws {
        let window = window()
        // An event finds its window by number among the app's windows.
        guard NSApp.window(withWindowNumber: window.windowNumber) === window else { return }
        let event = try #require(click(.leftMouseUp, in: window))
        #expect(LinkCursorTextField.isPlainClick(event, in: window))
    }

    /// The field editor asks its delegate (the field) through this selector
    /// before it opens a link.
    @Test func theFieldAnswersTheFieldEditorsLinkQuestion() {
        let field = LinkCursorTextField(labelWithString: "x")
        #expect(field.responds(to: #selector(NSTextViewDelegate.textView(_:clickedOnLink:at:))))
    }

    @Test func withNoHandlerTheLinkOpens() {
        let field = LinkCursorTextField(labelWithString: "x")
        #expect(LinkCursorTextField.linkClickHandler == nil)
        #expect(!field.textView(NSTextView(), clickedOnLink: "https://x.com/jack/status/20", at: 0))
    }
}
