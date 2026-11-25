@testable import MactrixiOS
import UIKit
import XCTest

/// MATRIX-245: "Reply in Thread" opens the thread screen with the keyboard
/// focus in its composer. The composer of a pushed screen is not in a window
/// at its first update, so the field keeps the request until it is.
@MainActor
final class ComposerFocusTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// A key window with an empty root view, for the text view to join.
    private func makeRootView() throws -> UIView {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        self.window = window
        return root.view
    }

    func testRequestBeforeTheWindowTakesTheFocusInTheWindow() throws {
        let textView = ComposerFocusableTextView()

        textView.requestFocus()
        XCTAssertFalse(textView.isFirstResponder)
        try makeRootView().addSubview(textView)

        XCTAssertTrue(textView.isFirstResponder)
    }

    func testRequestInTheWindowTakesTheFocusAtOnce() throws {
        let textView = ComposerFocusableTextView()
        try makeRootView().addSubview(textView)
        XCTAssertFalse(textView.isFirstResponder)

        textView.requestFocus()

        XCTAssertTrue(textView.isFirstResponder)
    }

    /// No request: a field that reaches the window leaves the keyboard down.
    func testNoRequestTakesNoFocus() throws {
        let textView = ComposerFocusableTextView()

        try makeRootView().addSubview(textView)

        XCTAssertFalse(textView.isFirstResponder)
    }
}
