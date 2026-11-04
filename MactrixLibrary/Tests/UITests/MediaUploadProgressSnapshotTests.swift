import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-107: the upload badge on a media local echo.
///
/// The height tests are the claim the row's height fingerprint relies on: the
/// badge is an overlay, so the body measures the same with and without it.
/// The snapshots are the local/agent-side gate (contract R-8), pinned to the
/// aqua appearance and rendered at a fixed 2x.
@MainActor
struct MediaUploadProgressSnapshotTests {
    private func host(_ view: some View, width: CGFloat = 360) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width, alignment: .leading)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private func uploading(_ percent: UInt64, index: UInt64 = 0) -> MediaUploadState {
        .uploading(MediaUploadSample(index: index, current: percent, total: 100))
    }

    /// A stand-in for a thumbnail, at a fixed size.
    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.5))
            .frame(width: 240, height: 135)
    }

    /// A stand-in for a one-line file row.
    private var fileRow: some View {
        AttachmentRowView(icon: Image(systemName: "doc"), title: "quarterly-report.pdf", subtitle: "1.2 MB")
    }

    // MARK: - Height neutrality

    @Test
    func cornerBadgeKeepsTheMediaHeight() {
        let bare = host(thumbnail.mediaUploadOverlay(nil, placement: .mediaCorner, cancel: {}))
        for state: MediaUploadState in [.queued, uploading(3), uploading(100)] {
            let badged = host(thumbnail.mediaUploadOverlay(state, placement: .mediaCorner, cancel: {}))
            #expect(badged.view.fittingSize.height == bare.view.fittingSize.height)
        }
    }

    @Test
    func trailingBadgeKeepsTheRowHeight() {
        let plain = host(fileRow)
        let bare = host(fileRow.mediaUploadOverlay(nil, placement: .rowTrailing, cancel: {}))
        #expect(bare.view.fittingSize.height == plain.view.fittingSize.height)

        for state: MediaUploadState in [.queued, uploading(3), uploading(100)] {
            let badged = host(fileRow.mediaUploadOverlay(state, placement: .rowTrailing, cancel: {}))
            #expect(badged.view.fittingSize.height == bare.view.fittingSize.height)
        }
    }

    // MARK: - Snapshots

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func badgeStates() {
        assertSnapshot(
            of: host(
                VStack(alignment: .leading, spacing: 8) {
                    MediaUploadProgressBadge(state: uploading(0), cancel: {})
                    MediaUploadProgressBadge(state: uploading(42), cancel: {})
                    MediaUploadProgressBadge(state: uploading(100), cancel: {})
                }
            ),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func badgeOnAThumbnail() {
        assertSnapshot(
            of: host(thumbnail.mediaUploadOverlay(uploading(67), placement: .mediaCorner, cancel: {})),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func badgeOnAFileRow() {
        assertSnapshot(
            of: host(fileRow.mediaUploadOverlay(uploading(18), placement: .rowTrailing, cancel: {})),
            as: .scaledImage
        )
    }
}
