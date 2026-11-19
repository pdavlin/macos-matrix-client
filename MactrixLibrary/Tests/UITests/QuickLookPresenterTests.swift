import AppKit
import Foundation
import SwiftUI
import Testing
@testable import UI

/// MATRIX-199: the app-wide Quick Look presenter holds the preview, its file
/// and the keyboard focus while the panel shows, and lets them go when the
/// panel closes.
@MainActor
struct QuickLookPresenterTests {
    /// A stand-in for `QLPreviewPanel`: it makes the presenter its controller
    /// when it shows, as the real panel does when the presenter is the first
    /// responder, and ends the control when it closes.
    final class FakePanel: QuickLookPanel {
        weak var presenter: QuickLookPresenter?
        var isPreviewVisible = false
        var reloads = 0

        func showPreview() {
            isPreviewVisible = true
            guard let presenter, !presenter.isControllingPanel, presenter.acceptsPreviewPanelControl(nil) else { return }
            presenter.panelControlDidBegin()
        }

        func reloadPreview() {
            reloads += 1
        }

        func closePreview() {
            guard isPreviewVisible else { return }
            isPreviewVisible = false
            if presenter?.isControllingPanel == true {
                presenter?.panelControlDidEnd()
            }
        }
    }

    /// Stands in for the SDK's `MediaFileHandle`: the file is on disk while
    /// the object lives.
    final class FileKeeper {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("QuickLookPresenterTests-\(UUID().uuidString).txt")
            try Data("media".utf8).write(to: url)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func makePresenter() -> (QuickLookPresenter, FakePanel) {
        let panel = FakePanel()
        let presenter = QuickLookPresenter(panel: { panel })
        panel.presenter = presenter
        return (presenter, panel)
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @Test func presentSetsTheURLAndShowsThePanel() throws {
        let (presenter, panel) = makePresenter()
        let keeper = try FileKeeper()

        presenter.present(url: keeper.url, keepAlive: keeper, in: nil)

        #expect(presenter.previewURL == keeper.url)
        #expect(panel.isPreviewVisible)
        #expect(presenter.isControllingPanel)
        #expect(presenter.numberOfPreviewItems(in: nil) == 1)
        #expect((presenter.previewPanel(nil, previewItemAt: 0)?.previewItemURL) == keeper.url)
    }

    @Test func theFileStaysWhileShownAndIsReleasedOnClose() throws {
        let (presenter, panel) = makePresenter()
        weak var weakKeeper: FileKeeper?
        let url: URL
        do {
            let keeper = try FileKeeper()
            weakKeeper = keeper
            url = keeper.url
            presenter.present(url: keeper.url, keepAlive: keeper, in: nil)
        }

        // The caller dropped its reference: the presenter keeps the file.
        #expect(weakKeeper != nil)
        #expect(fileExists(url))

        panel.closePreview()

        #expect(weakKeeper == nil)
        #expect(!fileExists(url))
        #expect(presenter.previewURL == nil)
        #expect(!presenter.isControllingPanel)
        #expect(presenter.numberOfPreviewItems(in: nil) == 0)
    }

    @Test func aRowRebuildDoesNotClearAnOpenPreview() throws {
        let (presenter, panel) = makePresenter()
        let table = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        weak var weakKeeper: FileKeeper?
        let url: URL
        do {
            // The row's hosting view and the row state that holds the file
            // handle, as `MediaFileController` does in a row.
            let row = NSHostingView(rootView: Text("image row"))
            table.addSubview(row)
            let keeper = try FileKeeper()
            weakKeeper = keeper
            url = keeper.url
            presenter.present(url: keeper.url, keepAlive: keeper, in: nil)

            // The table rebuilds the row: the old view leaves the table and
            // the row state goes with it.
            row.removeFromSuperview()
            table.addSubview(NSHostingView(rootView: Text("rebuilt image row")))
        }

        #expect(presenter.previewURL == url)
        #expect(presenter.isControllingPanel)
        #expect(panel.isPreviewVisible)
        #expect(weakKeeper != nil)
        #expect(fileExists(url))

        panel.closePreview()
        #expect(weakKeeper == nil)
    }

    @Test func anotherFileReplacesTheShownFile() throws {
        let (presenter, panel) = makePresenter()
        weak var weakFirst: FileKeeper?
        let second = try FileKeeper()
        do {
            let first = try FileKeeper()
            weakFirst = first
            presenter.present(url: first.url, keepAlive: first, in: nil)
        }

        presenter.present(url: second.url, keepAlive: second, in: nil)

        #expect(weakFirst == nil)
        #expect(presenter.previewURL == second.url)
        #expect(panel.reloads == 1)
        #expect(panel.isPreviewVisible)
    }

    @Test func thePresenterTakesTheFocusFromTheComposerAndGivesItBack() throws {
        let (presenter, panel) = makePresenter()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let composer = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        content.addSubview(composer)
        window.contentView = content
        window.makeFirstResponder(composer)
        #expect(window.firstResponder === composer)

        let keeper = try FileKeeper()
        presenter.present(url: keeper.url, keepAlive: keeper, in: window)

        #expect(window.firstResponder === presenter)
        #expect(presenter.superview === content)

        panel.closePreview()

        #expect(window.firstResponder === composer)
        #expect(presenter.superview == nil)
    }

    @Test func thePanelClosesWhenAnotherResponderTakesIt() async throws {
        let (presenter, panel) = makePresenter()
        let keeper = try FileKeeper()
        presenter.present(url: keeper.url, keepAlive: keeper, in: nil)

        // The panel moved to another controller and stays on the screen.
        presenter.panelControlDidEnd()
        #expect(presenter.previewURL == nil)

        try await Task.sleep(for: .milliseconds(50))
        #expect(!panel.isPreviewVisible)
    }

    @Test func thePresenterRefusesThePanelWithNothingToShow() {
        let (presenter, _) = makePresenter()
        #expect(!presenter.acceptsPreviewPanelControl(nil))
    }
}
