import Foundation
@testable import Mactrix
import MatrixRustSDK
import Models
import UniformTypeIdentifiers
import XCTest

/// S-38: regression coverage for the media rows' content-type mapping.
///
/// The inherited `MessageFileView` resolved its icon through
/// `UTType(mimeStr)` — the *identifier* initializer fed a MIME string — so
/// every file rendered with the generic icon. These tests pin the fixed
/// mapping (`UTType(mimeType:)`) on the file and audio rows.
@MainActor
final class MediaMessageViewTests: XCTestCase {
    private func makeSource() throws -> MediaSource {
        try MediaSource.fromUrl(url: "mxc://example.org/abcdef")
    }

    /// The row actions the media views now take (MATRIX-108). These tests
    /// read only the views' derived values, so the actions do nothing.
    private func makeRowActions(_ content: MessageActionSubject.Content) -> MessageActionTarget {
        let subject = MessageActionSubject(
            content: content,
            isOwn: false,
            eventId: "$event",
            canBeRepliedTo: true,
            isPinned: false,
            copyableText: nil
        )
        return MessageActionTarget(key: "$event", subject: subject) { _ in }
    }

    func testFileViewResolvesMimeTypeToUTType() throws {
        let content = try FileMessageContent(
            filename: "report.pdf",
            caption: nil,
            formattedCaption: nil,
            source: makeSource(),
            info: FileInfo(mimetype: "application/pdf", size: 1234, thumbnailInfo: nil, thumbnailSource: nil)
        )

        let view = MessageFileView(content: content, rowActions: makeRowActions(.file))

        XCTAssertEqual(view.contentType, .pdf)
        XCTAssertEqual(view.sizeText, UInt64(1234).formatted(.byteCount(style: .file)))
    }

    func testFileViewWithoutMimeTypeHasNoContentType() throws {
        let content = try FileMessageContent(
            filename: "blob",
            caption: nil,
            formattedCaption: nil,
            source: makeSource(),
            info: FileInfo(mimetype: nil, size: nil, thumbnailInfo: nil, thumbnailSource: nil)
        )

        let view = MessageFileView(content: content, rowActions: makeRowActions(.file))

        XCTAssertNil(view.contentType)
        XCTAssertNil(view.sizeText)
    }

    func testAudioViewSubtitleCarriesDurationAndSize() throws {
        let content = try AudioMessageContent(
            filename: "voice.ogg",
            caption: nil,
            formattedCaption: nil,
            source: makeSource(),
            info: AudioInfo(duration: 42, size: 131_072, mimetype: "audio/ogg"),
            audio: nil,
            voice: nil
        )

        let view = MessageAudioView(content: content, rowActions: makeRowActions(.audio))

        let expectedDuration = Duration.seconds(42.0).formatted(.time(pattern: .minuteSecond))
        let expectedSize = UInt64(131_072).formatted(.byteCount(style: .file))
        XCTAssertEqual(view.subtitle, "\(expectedDuration) · \(expectedSize)")
    }

    func testAudioViewSubtitleIsNilWithoutInfo() throws {
        let content = try AudioMessageContent(
            filename: "voice.ogg",
            caption: nil,
            formattedCaption: nil,
            source: makeSource(),
            info: nil,
            audio: nil,
            voice: nil
        )

        let view = MessageAudioView(content: content, rowActions: makeRowActions(.audio))

        XCTAssertNil(view.subtitle)
    }
}
