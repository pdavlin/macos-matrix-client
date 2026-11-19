#if os(macOS)
    import AppKit
    import Quartz

    /// The Quick Look panel as the presenter sees it: `QLPreviewPanel` in the
    /// app, a stand-in in tests.
    @MainActor
    public protocol QuickLookPanel: AnyObject {
        /// Whether the panel is on the screen.
        var isPreviewVisible: Bool { get }
        /// Shows the panel. The panel then finds its controller in the
        /// responder chain.
        func showPreview()
        /// Asks the data source for the items again.
        func reloadPreview()
        /// Takes the panel off the screen.
        func closePreview()
    }

    extension QLPreviewPanel: QuickLookPanel {
        public var isPreviewVisible: Bool { isVisible }
        public func showPreview() {
            makeKeyAndOrderFront(nil)
        }

        public func reloadPreview() {
            reloadData()
        }

        public func closePreview() {
            orderOut(nil)
        }
    }

    /// Shows a timeline media file in the Quick Look panel (MATRIX-199).
    ///
    /// The panel shows the items of its controller: the first object in the
    /// key window's responder chain that accepts control. An `NSTextView`
    /// accepts it, so while the composer had the keyboard focus (MATRIX-188)
    /// the composer took the panel and it showed "No items selected". A
    /// SwiftUI `.quickLookPreview` in a row cannot win against it.
    ///
    /// The presenter is a zero-size view that it puts in the window and makes
    /// the first responder while the panel shows, so it is the controller. It
    /// gives the focus back when the panel closes. It also holds the file and
    /// the object that keeps the file on disk (the SDK's `MediaFileHandle`),
    /// so a row that the table rebuilds or reuses does not take the preview
    /// with it. Both are released when the panel closes.
    @MainActor
    public final class QuickLookPresenter: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        /// One for the app, because the Quick Look panel is one for the app.
        public static let shared = QuickLookPresenter()

        private struct Item {
            let url: URL
            let keepAlive: AnyObject?
        }

        private var item: Item?
        private weak var restoreResponder: NSResponder?
        private let panelProvider: @MainActor () -> QuickLookPanel?

        /// Whether the panel uses this presenter as its controller.
        public private(set) var isControllingPanel = false

        /// The file the panel shows, or nil when no preview is open.
        public var previewURL: URL? { item?.url }

        /// - Parameter panel: Gets the panel when a preview starts. The app
        ///   uses the shared `QLPreviewPanel`.
        public init(panel: @escaping @MainActor () -> QuickLookPanel? = { QLPreviewPanel.shared() }) {
            panelProvider = panel
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        /// Shows `url` in the Quick Look panel.
        ///
        /// - Parameters:
        ///   - url: The local file.
        ///   - keepAlive: An object the file needs to stay on disk. The
        ///     presenter holds it until the panel closes or shows another file.
        ///   - window: The window the preview is for, normally the key window
        ///     when the user clicked. The presenter takes its first responder
        ///     while the panel shows.
        public func present(url: URL, keepAlive: AnyObject?, in window: NSWindow?) {
            item = Item(url: url, keepAlive: keepAlive)
            // The panel itself can be the key window when a preview is open.
            if let window = window is QLPreviewPanel ? NSApp.mainWindow : window {
                takeFocus(in: window)
            }
            guard let panel = panelProvider() else { return }
            if isControllingPanel {
                panel.reloadPreview()
            }
            panel.showPreview()
        }

        /// Puts the presenter in `window` and makes it the first responder,
        /// so the panel finds it before any text view.
        private func takeFocus(in window: NSWindow) {
            if self.window !== window {
                removeFromSuperview()
                restoreResponder = nil
                window.contentView?.addSubview(self)
            }
            if window.firstResponder !== self {
                restoreResponder = window.firstResponder
                window.makeFirstResponder(self)
            }
        }

        // MARK: - First responder

        override public var acceptsFirstResponder: Bool { true }

        // MARK: - Panel control

        // AppKit declares these on NSObject without an actor, and calls them
        // on the main thread.

        override public nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
            MainActor.assumeIsolated { item != nil }
        }

        override public nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            MainActor.assumeIsolated {
                panel?.dataSource = self
                panel?.delegate = self
                panelControlDidBegin()
            }
        }

        override public nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            MainActor.assumeIsolated {
                if panel?.dataSource === self { panel?.dataSource = nil }
                if panel?.delegate === self { panel?.delegate = nil }
                panelControlDidEnd()
            }
        }

        /// The panel made the presenter its controller.
        func panelControlDidBegin() {
            isControllingPanel = true
        }

        /// The panel closed, or another responder took it. Releases the file,
        /// gives the focus back, and closes a panel that would show nothing.
        func panelControlDidEnd() {
            isControllingPanel = false
            item = nil
            if let window, window.firstResponder === self {
                window.makeFirstResponder(restoreResponder)
            }
            restoreResponder = nil
            removeFromSuperview()

            // The panel stays open when another responder (the composer, on a
            // click into it) takes it, and then shows that responder's empty
            // list. Close it after the panel finishes the change.
            DispatchQueue.main.async { [weak self] in
                guard let self, !isControllingPanel, let panel = panelProvider(), panel.isPreviewVisible else { return }
                panel.closePreview()
            }
        }

        // MARK: - QLPreviewPanelDataSource

        public nonisolated func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
            MainActor.assumeIsolated { item == nil ? 0 : 1 }
        }

        public nonisolated func previewPanel(_: QLPreviewPanel!, previewItemAt _: Int) -> (any QLPreviewItem)! {
            let url = MainActor.assumeIsolated { previewURL }
            return url.map { $0 as NSURL }
        }
    }
#endif
