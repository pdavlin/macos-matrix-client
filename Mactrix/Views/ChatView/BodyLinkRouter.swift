import AppKit
import Core
import MessageFormatting
import Models
import SwiftUI

/// The one router for link clicks in message bodies (MATRIX-203): a Matrix
/// link opens in the app, an X or Bluesky post opens in the post peek
/// (MATRIX-201), and any other link opens the browser. The rule is
/// `BodyLinkRoute.route(isPlainClick:matrixLink:isPostPeekLink:)`.
///
/// Two paths get here: a click in an HTML body (`LinkCursorTextField`, which
/// passes only a plain left click) and a link of a body drawn with SwiftUI
/// `Text` (`openURLAction`). ⌘-click and the context menu's Open Link open
/// the browser.
///
/// The click does not know its window's `WindowState`. A Matrix link goes to
/// `MatrixLinkInbox`, and `MactrixApp` opens it in the key window, as it
/// does for a notification click.
@MainActor
enum BodyLinkRouter {
    /// Sets the body link handler. Call it once, when the app starts.
    static func install() {
        LinkCursorTextField.linkClickHandler = { url, field, rect in
            switch route(url, isPlainClick: true) {
            case let .matrix(link):
                MatrixLinkInbox.shared.post(link, url: url)
                return true
            case .postPeek:
                return PostPeekPresenter.peek(url, from: field, rect: rect)
            case .browser:
                return false
            }
        }
    }

    /// The `openURL` action for message bodies drawn with SwiftUI `Text`. A
    /// post link opens the browser here: the popover needs the link's
    /// rect, which `Text` does not give.
    static let openURLAction = OpenURLAction { url in
        let isPlainClick = NSApp.currentEvent.map { event in
            event.modifierFlags.isDisjoint(with: [.command, .option, .shift, .control])
        } ?? true
        guard case let .matrix(link) = route(url, isPlainClick: isPlainClick) else {
            return .systemAction(url)
        }
        MatrixLinkInbox.shared.post(link, url: url)
        return .handled
    }

    private static func route(_ url: URL, isPlainClick: Bool) -> BodyLinkRoute {
        BodyLinkRoute.route(
            isPlainClick: isPlainClick,
            matrixLink: MatrixLink(url: url),
            isPostPeekLink: PostPeekPresenter.peekLink(url) != nil
        )
    }
}

/// A Matrix link click that waits for the key window (MATRIX-203).
struct MatrixLinkRequest: Equatable {
    let id = UUID()
    let link: MatrixLink
    let url: URL
}

/// The Matrix link click that waits for a window to open it. `MactrixApp`
/// observes it and opens it in the key window, or brings a main window
/// forward when the key window is a room window of another room.
@MainActor @Observable
final class MatrixLinkInbox {
    static let shared = MatrixLinkInbox()

    var pending: MatrixLinkRequest?

    func post(_ link: MatrixLink, url: URL) {
        pending = MatrixLinkRequest(link: link, url: url)
    }
}
