import AppKit
import Models
import OSLog
import SwiftUI
import UI

/// Opens a plain click on an X or Bluesky post link of a message body in a
/// popover on the link (MATRIX-201). Credit: post-peek by tsvb
/// (https://github.com/tsvb/post-peek), MIT License.
///
/// The click comes from the body link router (`BodyLinkRouter`, MATRIX-203),
/// which gets only a plain left click: ⌘-click and the context menu's Open
/// Link open the browser as before. With the Settings switch off
/// (`PostPeekPreferences`), every post link opens the browser.
///
/// The post is read only on the click, from the Mac, over an ephemeral
/// `URLSession`: no cookies, no cache on disk, no Referer, a short timeout.
/// The posts and images of the last minutes stay in memory
/// (`PostPeekStore`). The contract §11 row of 2026-11-19 grants these
/// requests.
@MainActor
enum PostPeekPresenter {
    /// The post peek link of `url`, or nil when it is not an X or Bluesky
    /// post or the Settings switch is off.
    static func peekLink(_ url: URL) -> PostPeekLink? {
        guard PostPeekPreferences.isOn(in: .standard) else { return nil }
        return PostPeekLink(url: url)
    }

    /// Opens the post of `url` in a popover on the clicked link.
    ///
    /// - Returns: false when `url` is not a post peek link.
    static func peek(_ url: URL, from field: NSView, rect: CGRect) -> Bool {
        guard let link = peekLink(url) else { return false }
        show(link, clickedURL: url, from: field, rect: rect)
        return true
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = PostPeekReader.timeout
        configuration.timeoutIntervalForResource = PostPeekReader.timeout * 3
        return URLSession(configuration: configuration)
    }()

    private static let reader = PostPeekReader { request in
        try await session.data(for: request)
    }

    private static let store = PostPeekStore(
        fetchPost: { link in
            do {
                return try await reader.post(link)
            } catch {
                Logger.viewCycle.info("post peek: \(PostPeekReader.logName(of: error), privacy: .public)")
                throw error
            }
        },
        fetchImage: { url in try await reader.image(at: url) }
    )

    /// The popover on show. A new click closes it first.
    private static var current: PostPeekPopover?

    private static func show(_ link: PostPeekLink, clickedURL: URL, from field: NSView, rect: CGRect) {
        current?.close()
        let popover = PostPeekPopover(link: link, clickedURL: clickedURL, store: store)
        current = popover
        popover.show(from: field, rect: rect) {
            if current === popover {
                current = nil
            }
        }
    }
}

/// One post peek popover: an `NSPopover` on the clicked link, closed by Esc,
/// by a click outside it, or when a link in it opens the browser.
@MainActor
private final class PostPeekPopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let model: PostPeekModel
    private var keyMonitor: Any?
    private var onClose: (() -> Void)?

    init(link: PostPeekLink, clickedURL: URL, store: PostPeekStore) {
        model = PostPeekModel(link: link, fallbackURL: clickedURL, store: store)
        super.init()
    }

    func show(from field: NSView, rect: CGRect, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let content = PostPeekView(model: model)
            .environment(\.openURL, OpenURLAction { [weak self] url in
                self?.open(url) ?? .discarded
            })
            .environment(\.postPeekBrowserAction, OpenURLAction { [weak self] url in
                self?.close()
                return .systemAction(url)
            })
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // Below the link, or above it where the screen has no room.
        popover.show(relativeTo: rect, of: field, preferredEdge: field.isFlipped ? .maxY : .minY)

        // Esc closes the popover, also while the key window is the timeline's.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, popover.isShown else { return event }
            close()
            return nil
        }
    }

    func close() {
        popover.close()
    }

    /// An X or Bluesky post link opens in this popover. Any other link opens
    /// in the browser, and the popover closes.
    private func open(_ url: URL) -> OpenURLAction.Result {
        if let link = PostPeekLink(url: url) {
            model.open(link)
            return .handled
        }
        close()
        return .systemAction(url)
    }

    func popoverDidClose(_: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        onClose?()
        onClose = nil
    }
}
