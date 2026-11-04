import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-106: the composer with two pending attachments, an image with its
/// preview and a PDF with its type icon, above the paperclip and the caption
/// text. Same reference rules as `ComposerAffordanceSnapshotTests`: fixed 2x
/// scale, pinned appearance, and skipped in CI.
@MainActor
struct ComposerAttachmentSnapshotTests {
    /// A 160 x 120 PNG with two color bands, made in code.
    private func previewData() -> Data {
        let context = CGContext(
            data: nil,
            width: 160,
            height: 120,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 1)
        context.fill(CGRect(x: 0, y: 60, width: 160, height: 60))
        context.setFillColor(red: 0.95, green: 0.8, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 60))
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }

    private var attachments: [ComposerAttachment] {
        let preview = MediaThumbnail(data: previewData(), width: 160, height: 120, mimeType: "image/png")
        return [
            ComposerAttachment(
                source: .file(URL(fileURLWithPath: "/tmp/beach-sunset.jpg")),
                filename: "beach-sunset.jpg",
                kind: .image,
                mimeType: "image/jpeg",
                byteCount: 3_400_000,
                measurement: MediaMeasurement(width: 4032, height: 3024, preview: preview)
            ),
            ComposerAttachment(
                source: .file(URL(fileURLWithPath: "/tmp/quarterly-report-final-v2.pdf")),
                filename: "quarterly-report-final-v2.pdf",
                kind: .file,
                mimeType: "application/pdf",
                byteCount: 1_250_000,
                measurement: .empty
            ),
        ]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func composerWithTwoAttachments() {
        let composer = VStack(alignment: .leading, spacing: 0) {
            ComposerAttachmentStrip(attachments: attachments, onRemove: { _ in })
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                Text("Photos from the trip")
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .font(.system(size: 13))
        .frame(width: 460)
        .background(Color.white)

        let controller = NSHostingController(rootView: composer)
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        assertSnapshot(of: controller, as: .scaledImage)
    }

    @Test func iconFollowsTheKind() {
        #expect(ComposerAttachmentPreview.iconName(for: .image) == "photo")
        #expect(ComposerAttachmentPreview.iconName(for: .video) == "film")
        #expect(ComposerAttachmentPreview.iconName(for: .audio) == "waveform")
        #expect(ComposerAttachmentPreview.iconName(for: .file) == "doc")
    }
}
