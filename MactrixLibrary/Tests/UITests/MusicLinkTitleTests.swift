import AppKit
@testable import MessageFormatting
import Models
import SnapshotTesting
import SwiftUI
import Testing
import Tokens

/// MATRIX-191: a Spotify link that shows its URL shows `Artist · Name` when
/// the title store holds the link's title. The glyph, the bar, the body
/// color, and the song.link target stay.
///
/// Each test has its own store, so no test reads the app's shared store.
@MainActor
struct MusicLinkTitleTests {
    static let trackId = "4cOdK2wGLETKBW3PvgPWqT"
    static let albumId = "6N9PS4QXF1D0OWPk0Sxtb4"
    static let posted = "https://open.spotify.com/track/\(trackId)?si=0123456789abcdef"
    static let album = "https://open.spotify.com/album/\(albumId)"
    static let trackTarget = "https://song.link/https://open.spotify.com/track/\(trackId)"

    static let track = #"<p><a href="\#(posted)">\#(posted)</a></p>"#
    static let albumBody = #"<p>the whole album: <a href="\#(album)">\#(album)</a> is good</p>"#
    static let ownText = #"<p>listen to <a href="\#(posted)">this song</a> now</p>"#

    /// Wide enough for the track title on one line.
    static let wideWidth: CGFloat = 360
    /// Narrow enough that the album body wraps its title.
    static let narrowWidth: CGFloat = 200

    private func titles(track: Bool = true, album: Bool = true) throws -> MusicLinkTitleStore {
        let store = MusicLinkTitleStore()
        if track {
            try store.remember(
                MusicLinkTitle(artist: "Rick Astley", name: "Never Gonna Give You Up"),
                for: #require(MusicLink.classify(Self.posted))
            )
        }
        if album {
            try store.remember(
                MusicLinkTitle(artist: "Rick Astley", name: "Whenever You Need Somebody"),
                for: #require(MusicLink.classify(Self.album))
            )
        }
        return store
    }

    private func marked(_ html: String, titles: MusicLinkTitleStore?) -> NSAttributedString {
        AttributedTextView(
            attributedString: parseFormattedBody(html, baseFontSize: 13, marksMusicLinks: true, musicLinkTitles: titles)
        ).attributedString
    }

    private func range(of text: String, in string: NSAttributedString) throws -> NSRange {
        let range = (string.string as NSString).range(of: text)
        try #require(range.location != NSNotFound)
        return range
    }

    // MARK: Text

    @Test func aTrackLinkShowsArtistAndSong() throws {
        let string = try marked(Self.track, titles: titles())
        let title = "Rick Astley \u{00B7} Never Gonna Give You Up"
        #expect(string.string.replacingOccurrences(of: "\u{FFFC}", with: "") == title)
        #expect(!string.string.contains("open.spotify.com"))

        let range = try range(of: title, in: string)
        var effective = NSRange()
        #expect(string.attribute(.musicLinkMarker, at: range.location, effectiveRange: &effective) as? Bool == true)
        #expect(effective == range)
        #expect((string.attribute(.musicLinkTarget, at: range.location, effectiveRange: nil) as? URL)?.absoluteString
            == Self.trackTarget)
        #expect(string.attribute(.link, at: range.location, effectiveRange: nil) == nil)
        #expect(string.attribute(.foregroundColor, at: range.location, effectiveRange: nil) == nil)
        #expect(string.attribute(.musicLinkHelp, at: range.location, effectiveRange: nil) as? String
            == "Replaced automatically\n\(Self.posted)")

        // The glyph keeps its place before the text, with the same target
        // and tooltip.
        let glyphIndex = range.location - 1
        #expect(string.attribute(.attachment, at: glyphIndex, effectiveRange: nil) is MusicLinkGlyph)
        #expect((string.attribute(.musicLinkTarget, at: glyphIndex, effectiveRange: nil) as? URL)?.absoluteString
            == Self.trackTarget)
        #expect(string.attribute(.musicLinkHelp, at: glyphIndex, effectiveRange: nil) as? String
            == "Replaced automatically\n\(Self.posted)")
    }

    @Test func anAlbumLinkShowsArtistAndAlbum() throws {
        let string = try marked(Self.albumBody, titles: titles())
        #expect(string.string.replacingOccurrences(of: "\u{FFFC}", with: "")
            == "the whole album: Rick Astley \u{00B7} Whenever You Need Somebody is good")
    }

    @Test func withNoTitleTheLinkShowsItsURL() throws {
        let withNone = try marked(Self.track, titles: titles(track: false))
        let withNoStore = marked(Self.track, titles: nil)
        for string in [withNone, withNoStore] {
            #expect(string.string.replacingOccurrences(of: "\u{FFFC}", with: "") == Self.posted)
            let range = try range(of: Self.posted, in: string)
            #expect(string.attribute(.musicLinkHelp, at: range.location, effectiveRange: nil) == nil)
            #expect(string.attribute(.musicLinkMarker, at: range.location, effectiveRange: nil) as? Bool == true)
        }
    }

    @Test func aLinkWithItsOwnTextKeepsIt() throws {
        let string = try marked(Self.ownText, titles: titles())
        #expect(string.string.replacingOccurrences(of: "\u{FFFC}", with: "") == "listen to this song now")
        let range = try range(of: "this song", in: string)
        #expect(string.attribute(.musicLinkHelp, at: range.location, effectiveRange: nil) == nil)
    }

    @Test func withTheSwitchOffTheLinkIsPlain() throws {
        let string = try AttributedTextView(
            attributedString: parseFormattedBody(Self.track, baseFontSize: 13, musicLinkTitles: titles())
        ).attributedString
        #expect(string.string == Self.posted)
    }

    @Test func onlyLinksThatShowTheirURLAreCandidates() {
        let html = Self.track + Self.ownText + Self.albumBody
            + #"<a href="https://www.deezer.com/track/3135556">https://www.deezer.com/track/3135556</a>"#
        let candidates = musicLinkTitleCandidates(inFormattedBody: html, baseFontSize: 13).map(\.canonicalURL.absoluteString)
        #expect(candidates == ["https://open.spotify.com/track/\(Self.trackId)", Self.album])
    }

    // MARK: Click areas and layout

    @Test func theClickAreasCarryTheTooltip() throws {
        let string = try marked(Self.track, titles: titles())
        let targets = MusicLinkBar.targets(for: string, in: CGRect(x: 0, y: 0, width: Self.wideWidth, height: 1000))
        #expect(targets.count == 1)
        #expect(targets.first?.help == "Replaced automatically\n\(Self.posted)")
        #expect(targets.first?.text == "Rick Astley \u{00B7} Never Gonna Give You Up")
        #expect(targets.first?.url.absoluteString == Self.trackTarget)

        let plain = marked(Self.track, titles: nil)
        #expect(MusicLinkBar.targets(for: plain, in: CGRect(x: 0, y: 0, width: Self.wideWidth, height: 1000)).first?.help == nil)
    }

    @Test func theBarFollowsTheTitle() throws {
        let bounds = CGRect(x: 0, y: 0, width: Self.wideWidth, height: 1000)
        let title = try marked(Self.track, titles: titles())
        let url = marked(Self.track, titles: nil)
        let titleBars = MusicLinkBar.rects(for: title, in: bounds)
        let urlBars = MusicLinkBar.rects(for: url, in: bounds)
        #expect(titleBars.count == 1)
        #expect(urlBars.count == 2)
        let narrowBars = try MusicLinkBar.rects(for: marked(Self.albumBody, titles: titles()), in: CGRect(
            x: 0, y: 0, width: Self.narrowWidth, height: 1000
        ))
        #expect(narrowBars.count == 2)
    }

    /// The timeline measures a row by laying out the same view, so the view
    /// with a title has the height of the title's string, and it is shorter
    /// than the same body with the long URL.
    @Test func theMeasureFollowsTheTitle() throws {
        let store = try titles()
        let withTitle = hosted(Self.track, width: Self.wideWidth, titles: store)
        let withURL = hosted(Self.track, width: Self.wideWidth, titles: nil)
        #expect(withTitle.view.fittingSize.height == height(of: marked(Self.track, titles: store), width: Self.wideWidth))
        #expect(withTitle.view.fittingSize.height < withURL.view.fittingSize.height)
    }

    /// The body reads the store as it draws, so a title that arrives draws
    /// the body again with the title.
    @Test func aTitleThatArrivesDrawsTheBodyAgain() async throws {
        let store = MusicLinkTitleStore()
        let controller = hosted(Self.track, width: Self.wideWidth, titles: store)
        let field = try #require(Self.first(NSTextField.self, in: controller.view))
        #expect(field.attributedStringValue.string.contains(Self.posted))

        try store.remember(
            MusicLinkTitle(artist: "Rick Astley", name: "Never Gonna Give You Up"),
            for: #require(MusicLink.classify(Self.posted))
        )
        for _ in 0 ..< 50 where field.attributedStringValue.string.contains(Self.posted) {
            await Task.yield()
            controller.view.layoutSubtreeIfNeeded()
        }
        #expect(field.attributedStringValue.string.contains("Rick Astley \u{00B7} Never Gonna Give You Up"))
    }

    private func height(of string: NSAttributedString, width: CGFloat) -> CGFloat {
        let field = NSTextField(labelWithAttributedString: string)
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        field.preferredMaxLayoutWidth = width
        let bounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)
        return ceil(field.cell?.cellSize(forBounds: bounds).height ?? 0)
    }

    private func hosted(_ html: String, width: CGFloat, titles: MusicLinkTitleStore?) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                FormattedBodyText(html: html, baseFontSize: 13, imageLoader: nil, marksMusicLinks: true, musicLinkTitles: titles)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: width)
            )
        )
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private static func first<T: NSView>(_: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = first(T.self, in: subview) { return match }
        }
        return nil
    }

    // MARK: Snapshots

    /// A body alone, as `MusicLinkSnapshotTests` draws one. The glyph is an
    /// SF Symbol that the OS owns, so the precision lets one changed glyph
    /// pass, and a layout or color change fail.
    private func snapshotBody(
        _ html: String,
        width: CGFloat,
        titles: MusicLinkTitleStore?,
        appearance: NSAppearance.Name
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                FormattedBodyText(
                    html: html,
                    baseFontSize: CGFloat(TypographyToken.defaultBaseFontSize),
                    imageLoader: nil,
                    marksMusicLinks: true,
                    musicLinkTitles: titles
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .leading)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.appearance = NSAppearance(named: appearance)
        controller.view.frame.size = controller.view.fittingSize
        return controller
    }

    private func assertBody(
        _ html: String,
        width: CGFloat,
        titles: MusicLinkTitleStore?,
        appearance: NSAppearance.Name,
        testName: String = #function
    ) {
        assertSnapshot(
            of: snapshotBody(html, width: width, titles: titles, appearance: appearance),
            as: .scaledImage(precision: 0.9995),
            testName: testName
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func trackTitleLight() throws {
        try assertBody(Self.track, width: Self.wideWidth, titles: titles(), appearance: .aqua)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func trackTitleDark() throws {
        try assertBody(Self.track, width: Self.wideWidth, titles: titles(), appearance: .darkAqua)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func albumTitleLight() throws {
        try assertBody(Self.albumBody, width: Self.wideWidth + 100, titles: titles(), appearance: .aqua)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func albumTitleDark() throws {
        try assertBody(Self.albumBody, width: Self.wideWidth + 100, titles: titles(), appearance: .darkAqua)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func wrappedTitleLight() throws {
        try assertBody(Self.albumBody, width: Self.narrowWidth, titles: titles(), appearance: .aqua)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func wrappedTitleDark() throws {
        try assertBody(Self.albumBody, width: Self.narrowWidth, titles: titles(), appearance: .darkAqua)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func fallbackURLLight() {
        assertBody(Self.track, width: Self.wideWidth, titles: MusicLinkTitleStore(), appearance: .aqua)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func fallbackURLDark() {
        assertBody(Self.track, width: Self.wideWidth, titles: MusicLinkTitleStore(), appearance: .darkAqua)
    }
}
