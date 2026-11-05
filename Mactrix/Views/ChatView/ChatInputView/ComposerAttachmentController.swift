import AppKit
import Core
import Models
import Observation
import OSLog
import UniformTypeIdentifiers
import Utils

/// Holds the pending attachments of one composer (MATRIX-106).
///
/// This type is glue only. The rules live in `Models` (`MediaSendKind`,
/// `ComposerPasteDecision`, `PastedImage`, `MediaSendPlan`), the measurement
/// in `Core.MediaAttachmentMeasurer`, and the SDK send in
/// `Core.LiveTimeline.sendMedia(_:)`.
///
/// Attachments come in three ways: the paperclip button
/// (`presentOpenPanel()`), paste, and drop (`takeContent(of:)`, which the
/// text view calls).
@MainActor @Observable
final class ComposerAttachmentController {
    /// The pending attachments, in send order. `ChatInputView` draws the
    /// chips from this.
    private(set) var attachments: [ComposerAttachment] = []

    /// The measurement task for each attachment that is not measured yet.
    @ObservationIgnored private var measureTasks: [ComposerAttachment.ID: Task<Void, Never>] = [:]

    var isEmpty: Bool {
        attachments.isEmpty
    }

    // MARK: - Add

    /// Adds files on disk. Folders and files that cannot be read are
    /// skipped and logged.
    ///
    /// - Parameter urls: file URLs from the open panel, a paste, or a drop.
    func add(fileURLs urls: [URL]) {
        for url in urls where url.isFileURL {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            guard values?.isDirectory != true else {
                Logger.viewCycle.info("attachment skipped, it is a folder: \(url.lastPathComponent)")
                continue
            }
            guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
                Logger.viewCycle.error("attachment skipped, the file cannot be read: \(url.lastPathComponent)")
                continue
            }
            append(.file(at: url, byteCount: values?.fileSize.map { UInt64($0) }))
        }
    }

    /// Adds pasted or dropped image bytes. A TIFF becomes PNG first, because
    /// clients cannot show TIFF.
    ///
    /// - Parameters:
    ///   - data: the encoded image.
    ///   - contentType: the type of `data`.
    func add(imageData data: Data, contentType: UTType) {
        var bytes = data
        var type = contentType
        if PastedImage.convertsToPNG(contentType) {
            guard let png = MediaProbe.pngData(fromImageData: data) else {
                Logger.viewCycle.error("pasted image skipped, the conversion to PNG failed")
                return
            }
            bytes = png
            type = .png
        }
        let filename = PastedImage.filename(date: .now, contentType: type)
        append(.imageData(bytes, contentType: type, filename: filename))
    }

    /// Adds the files or the image on a pasteboard, if the paste rule says
    /// to (`ComposerPasteDecision`).
    ///
    /// - Parameter pasteboard: the general pasteboard for a paste, or the
    ///   dragging pasteboard for a drop.
    /// - Returns: true if it took the content. False means the text view
    ///   handles it as text.
    func takeContent(of pasteboard: NSPasteboard) -> Bool {
        let content = Self.pasteboardContent(pasteboard)
        switch content.decision {
        case .text:
            return false
        case .attachFiles:
            add(fileURLs: content.fileURLs)
            return true
        case .attachImage:
            guard
                let imageType = content.imageType,
                let data = pasteboard.data(forType: NSPasteboard.PasteboardType(imageType.identifier))
            else { return false }
            add(imageData: data, contentType: imageType)
            return true
        }
    }

    /// Whether a drag holds files or an image the composer takes.
    ///
    /// - Parameter pasteboard: the dragging pasteboard.
    func acceptsDrop(of pasteboard: NSPasteboard) -> Bool {
        Self.pasteboardContent(pasteboard).decision != .text
    }

    /// Opens the file picker (multiple selection) and adds the picked files.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Attach", comment: "The open panel button that adds the picked files to the composer")
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard response == .OK, let urls = panel?.urls else { return }
            self?.add(fileURLs: urls)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    // MARK: - Remove

    /// Removes one attachment and stops its measurement.
    ///
    /// - Parameter id: the attachment id.
    func remove(_ id: ComposerAttachment.ID) {
        measureTasks.removeValue(forKey: id)?.cancel()
        attachments.removeAll { $0.id == id }
    }

    /// Removes the newest attachment (Esc in the text field).
    ///
    /// - Returns: true if there was one to remove.
    func removeLast() -> Bool {
        guard let last = attachments.last else { return false }
        remove(last.id)
        return true
    }

    /// Removes all attachments, after a send.
    func clear() {
        measureTasks.values.forEach { $0.cancel() }
        measureTasks = [:]
        attachments = []
    }

    // MARK: - Send

    /// Waits for every measurement to finish.
    ///
    /// - Returns: the attachments, in send order, all measured.
    func measuredAttachments() async -> [ComposerAttachment] {
        for task in Array(measureTasks.values) {
            await task.value
        }
        return attachments
    }

    // MARK: - Private

    private func append(_ attachment: ComposerAttachment) {
        attachments.append(attachment)
        // Detached: ImageIO and AVFoundation work stays off the main actor.
        let measuring = Task.detached(priority: .userInitiated) {
            await MediaAttachmentMeasurer.measure(attachment)
        }
        measureTasks[attachment.id] = Task { [weak self] in
            let measurement = await measuring.value
            guard let self, !Task.isCancelled else { return }
            if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
                attachments[index].measurement = measurement
            }
            measureTasks[attachment.id] = nil
        }
    }

    /// What a pasteboard holds, and the paste rule for it.
    private struct PasteboardContent {
        let decision: ComposerPasteDecision
        let fileURLs: [URL]
        let imageType: UTType?
    }

    private static func pasteboardContent(_ pasteboard: NSPasteboard) -> PasteboardContent {
        let types = pasteboard.types ?? []
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let imageType = PastedImage.preferredType(from: types.compactMap { UTType($0.rawValue) })
        let hasText = types.contains(.string) || types.contains(.rtf) || types.contains(.rtfd) || types.contains(.html)
        let decision = ComposerPasteDecision.decide(
            hasDraftText: types.contains(DynamicTextView.draftTextPasteboardType),
            fileURLCount: fileURLs.count,
            hasImageData: imageType != nil,
            hasText: hasText
        )
        return PasteboardContent(decision: decision, fileURLs: fileURLs, imageType: imageType)
    }
}
