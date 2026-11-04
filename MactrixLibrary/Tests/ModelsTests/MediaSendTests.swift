import Foundation
import Models
import Testing
import UniformTypeIdentifiers

/// MATRIX-106: the pure rules of composer media send. The kind for a type,
/// the paste rule, the pasted image type and name, the thumbnail rule, the
/// single or gallery plan, the caption, the info fields, and the local echo
/// match for the cancel hook.
struct MediaSendKindTests {
    @Test(arguments: ["jpg", "jpeg", "png", "gif", "webp"])
    func inlineImagesAreImages(fileExtension: String) {
        #expect(MediaSendKind(contentType: UTType(filenameExtension: fileExtension)) == .image)
    }

    @Test(arguments: ["heic", "tiff", "psd", "svg"])
    func otherImagesAreFiles(fileExtension: String) {
        #expect(MediaSendKind(contentType: UTType(filenameExtension: fileExtension)) == .file)
    }

    @Test(arguments: ["mp4", "mov", "m4v"])
    func inlineVideosAreVideos(fileExtension: String) {
        #expect(MediaSendKind(contentType: UTType(filenameExtension: fileExtension)) == .video)
    }

    @Test func otherMoviesAreFiles() {
        #expect(MediaSendKind(contentType: UTType(filenameExtension: "avi")) == .file)
    }

    @Test(arguments: ["mp3", "m4a", "wav"])
    func audioIsAudio(fileExtension: String) {
        #expect(MediaSendKind(contentType: UTType(filenameExtension: fileExtension)) == .audio)
    }

    @Test func documentsAndUnknownTypesAreFiles() {
        #expect(MediaSendKind(contentType: .pdf) == .file)
        #expect(MediaSendKind(contentType: UTType(filenameExtension: "zip")) == .file)
        #expect(MediaSendKind(contentType: nil) == .file)
    }

    @Test func fileAttachmentTakesNameKindAndMimeFromTheURL() {
        let attachment = ComposerAttachment.file(at: URL(fileURLWithPath: "/tmp/Trip Photos/beach.JPG"), byteCount: 42)
        #expect(attachment.filename == "beach.JPG")
        #expect(attachment.kind == .image)
        #expect(attachment.mimeType == "image/jpeg")
        #expect(attachment.byteCount == 42)
        #expect(attachment.measurement == nil)
        #expect(!attachment.isReady)
    }

    @Test func imageDataAttachmentCountsTheBytes() {
        let attachment = ComposerAttachment.imageData(Data([1, 2, 3]), contentType: .png, filename: "a.png")
        #expect(attachment.kind == .image)
        #expect(attachment.mimeType == "image/png")
        #expect(attachment.byteCount == 3)
        #expect(attachment.source == .data(Data([1, 2, 3])))
    }
}

struct MediaThumbnailPolicyTests {
    @Test func smallStillImageGetsNoThumbnail() {
        #expect(!MediaThumbnailPolicy.shouldThumbnailImage(width: 640, height: 480, byteCount: 200_000, isAnimated: false))
    }

    @Test func wideImageGetsAThumbnail() {
        #expect(MediaThumbnailPolicy.shouldThumbnailImage(width: 4032, height: 300, byteCount: 200_000, isAnimated: false))
    }

    @Test func tallImageGetsAThumbnail() {
        #expect(MediaThumbnailPolicy.shouldThumbnailImage(width: 300, height: 801, byteCount: nil, isAnimated: false))
    }

    @Test func heavyImageGetsAThumbnail() {
        #expect(MediaThumbnailPolicy.shouldThumbnailImage(width: 500, height: 500, byteCount: 2_000_000, isAnimated: false))
    }

    @Test func animatedImageNeverGetsAThumbnail() {
        #expect(!MediaThumbnailPolicy.shouldThumbnailImage(width: 4000, height: 4000, byteCount: 9_000_000, isAnimated: true))
    }

    @Test func thumbnailFilenameFollowsTheType() {
        #expect(MediaThumbnailPolicy.filename(forMimeType: "image/png") == "thumbnail.png")
        #expect(MediaThumbnailPolicy.filename(forMimeType: "image/jpeg") == "thumbnail.jpg")
    }
}

struct PastedImageTests {
    @Test func pngWinsOverTiff() {
        #expect(PastedImage.preferredType(from: [.tiff, .png]) == .png)
    }

    @Test func tiffAloneIsReadAndConverted() throws {
        let type = try #require(PastedImage.preferredType(from: [.utf8PlainText, .tiff]))
        #expect(type == .tiff)
        #expect(PastedImage.convertsToPNG(type))
        #expect(!PastedImage.convertsToPNG(.png))
    }

    @Test func noImageTypeGivesNil() {
        #expect(PastedImage.preferredType(from: [.utf8PlainText, .rtf]) == nil)
        #expect(PastedImage.preferredType(from: []) == nil)
    }

    @Test func filenameHasTheDateTimeAndExtension() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        // 2026-11-04 15:45:20 UTC.
        let date = Date(timeIntervalSince1970: 1_793_807_120)
        #expect(PastedImage.filename(date: date, contentType: .png, timeZone: utc) == "Pasted image 2026-11-04 at 15.45.20.png")
        #expect(PastedImage.filename(date: date, contentType: .jpeg, timeZone: utc) == "Pasted image 2026-11-04 at 15.45.20.jpeg")
    }
}

struct ComposerPasteDecisionTests {
    private func decide(
        draft: Bool = false,
        files: Int = 0,
        image: Bool = false,
        text: Bool = false
    ) -> ComposerPasteDecision {
        ComposerPasteDecision.decide(hasDraftText: draft, fileURLCount: files, hasImageData: image, hasText: text)
    }

    @Test func plainTextPastesAsText() {
        #expect(decide(text: true) == .text)
    }

    @Test func composerDraftTextAlwaysPastesAsText() {
        #expect(decide(draft: true, files: 1, image: true, text: true) == .text)
    }

    @Test func finderFilesAttachEvenWithTheirNamesAsText() {
        #expect(decide(files: 2, image: true, text: true) == .attachFiles)
    }

    @Test func screenshotAttachesAsImage() {
        #expect(decide(image: true) == .attachImage)
    }

    @Test func textWithAPictureOfItPastesAsText() {
        #expect(decide(image: true, text: true) == .text)
    }

    @Test func emptyPasteboardIsText() {
        #expect(decide() == .text)
    }
}

struct MediaSendPlanTests {
    private func attachment(_ name: String, kind: MediaSendKind = .image) -> ComposerAttachment {
        ComposerAttachment(
            source: .file(URL(fileURLWithPath: "/tmp/\(name)")),
            filename: name,
            kind: kind,
            mimeType: nil,
            byteCount: nil,
            measurement: .empty
        )
    }

    @Test func noAttachmentGivesNoPlan() {
        #expect(MediaSendPlan(attachments: []) == nil)
    }

    @Test func oneAttachmentIsASingleSend() {
        let one = attachment("a.png")
        #expect(MediaSendPlan(attachments: [one]) == .single(one))
    }

    @Test func twoOrMoreAttachmentsAreAGalleryInOrder() {
        let items = [attachment("a.png"), attachment("b.mov", kind: .video), attachment("c.pdf", kind: .file)]
        let plan = MediaSendPlan(attachments: items)
        #expect(plan == .gallery(items))
        #expect(plan?.attachments.map(\.filename) == ["a.png", "b.mov", "c.pdf"])
    }

    @Test func requestCarriesCaptionAndReplyTarget() throws {
        let request = try #require(MediaSendRequest.make(
            attachments: [attachment("a.png")],
            draftText: "look",
            inReplyTo: "$event:example.org"
        ))
        #expect(request.caption == MediaCaption(markdown: "look", mentionedUserIds: []))
        #expect(request.inReplyTo == "$event:example.org")
    }

    @Test func requestWithNoAttachmentIsNil() {
        #expect(MediaSendRequest.make(attachments: [], draftText: "text only", inReplyTo: nil) == nil)
    }
}

struct MediaCaptionTests {
    @Test func emptyTextGivesNoCaption() {
        #expect(MediaCaption.make(fromDraftText: "") == nil)
        #expect(MediaCaption.make(fromDraftText: "  \n\t ") == nil)
    }

    @Test func captionIsTrimmed() {
        #expect(MediaCaption.make(fromDraftText: "\n  **nice** view \n") == MediaCaption(markdown: "**nice** view", mentionedUserIds: []))
    }

    @Test func mentionChipBecomesAPillAndAMention() throws {
        let alice = MentionTarget(userId: "@alice:example.org", displayName: "Alice")
        let draft = MentionMarkdown.draftText(for: [.text("for "), .mention(alice)])
        let caption = try #require(MediaCaption.make(fromDraftText: draft))
        #expect(caption.markdown == MentionMarkdown.outgoingMessage(fromDraftText: draft).markdown)
        #expect(caption.markdown.contains("https://matrix.to/#/@alice:example.org"))
        #expect(caption.mentionedUserIds == ["@alice:example.org"])
    }
}

struct MediaSendInfoTests {
    private let thumbnail = MediaThumbnail(data: Data([9, 9]), width: 800, height: 600, mimeType: "image/jpeg")

    private func attachment(_ kind: MediaSendKind, measurement: MediaMeasurement?) -> ComposerAttachment {
        ComposerAttachment(
            source: .file(URL(fileURLWithPath: "/tmp/x")),
            filename: "x",
            kind: kind,
            mimeType: "type/x",
            byteCount: 1234,
            measurement: measurement
        )
    }

    private var fullMeasurement: MediaMeasurement {
        MediaMeasurement(width: 4000, height: 3000, duration: 12.5, isAnimated: false, thumbnail: thumbnail)
    }

    @Test func imageKeepsSizeAndThumbnailButNoDuration() throws {
        let info = MediaSendInfo(attachment: attachment(.image, measurement: fullMeasurement))
        #expect(info.width == 4000)
        #expect(info.height == 3000)
        #expect(info.duration == nil)
        #expect(info.isAnimated == false)
        #expect(info.mimeType == "type/x")
        #expect(info.size == 1234)
        let sent = try #require(info.thumbnail)
        #expect(sent.filename == "thumbnail.jpg")
        #expect(sent.width == 800)
        #expect(sent.height == 600)
        #expect(sent.size == 2)
        #expect(sent.mimeType == "image/jpeg")
    }

    @Test func videoKeepsSizeDurationAndPoster() {
        let info = MediaSendInfo(attachment: attachment(.video, measurement: fullMeasurement))
        #expect(info.width == 4000)
        #expect(info.duration == 12.5)
        #expect(info.isAnimated == nil)
        #expect(info.thumbnail != nil)
    }

    @Test func audioKeepsDurationOnly() {
        let info = MediaSendInfo(attachment: attachment(.audio, measurement: fullMeasurement))
        #expect(info.duration == 12.5)
        #expect(info.width == nil)
        #expect(info.height == nil)
        #expect(info.thumbnail == nil)
    }

    @Test func fileKeepsTypeAndSizeOnly() {
        let info = MediaSendInfo(attachment: attachment(.file, measurement: fullMeasurement))
        #expect(info.mimeType == "type/x")
        #expect(info.size == 1234)
        #expect(info.width == nil)
        #expect(info.duration == nil)
        #expect(info.thumbnail == nil)
    }

    @Test func unmeasuredImageHasTypeAndSizeOnly() {
        let info = MediaSendInfo(attachment: attachment(.image, measurement: nil))
        #expect(info.size == 1234)
        #expect(info.width == nil)
        #expect(info.thumbnail == nil)
    }
}

struct MediaSendCorrelationTests {
    private let first = MediaSendTicket(filenames: ["a.png"], isGallery: false)
    private let second = MediaSendTicket(filenames: ["a.png"], isGallery: false)
    private let gallery = MediaSendTicket(filenames: ["b.png", "c.png"], isGallery: true)

    @Test func oldestOpenTicketWithTheFilenameMatches() {
        let index = MediaSendCorrelation.ticketIndex(forTransactionId: "t1", filename: "a.png", in: [gallery, first, second])
        #expect(index == 1)
    }

    @Test func boundTicketMatchesFirst() {
        var bound = second
        bound.localEchoTransactionId = "t2"
        let index = MediaSendCorrelation.ticketIndex(forTransactionId: "t2", filename: "a.png", in: [first, bound])
        #expect(index == 1)
    }

    @Test func ticketBoundToAnotherEchoIsSkipped() {
        var bound = first
        bound.localEchoTransactionId = "t1"
        let index = MediaSendCorrelation.ticketIndex(forTransactionId: "t2", filename: "a.png", in: [bound, second])
        #expect(index == 1)
    }

    @Test func pathFilenameMatchesByLastComponent() {
        let index = MediaSendCorrelation.ticketIndex(forTransactionId: "t1", filename: "/var/tmp/a.png", in: [first])
        #expect(index == 0)
    }

    @Test func galleryEchoMatchesTheOldestGallery() {
        let index = MediaSendCorrelation.ticketIndex(forTransactionId: "t1", filename: nil, in: [first, gallery])
        #expect(index == 1)
    }

    @Test func noMatchGivesNil() {
        #expect(MediaSendCorrelation.ticketIndex(forTransactionId: "t1", filename: "z.png", in: [first, gallery]) == nil)
        #expect(MediaSendCorrelation.ticketIndex(forTransactionId: "t1", filename: nil, in: [first]) == nil)
    }
}
