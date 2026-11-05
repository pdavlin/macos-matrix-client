import Foundation
import MatrixRustSDK
import Models

// MARK: - Upload progress of a local echo (MATRIX-107)

/// The witness for `Models.EventTimelineItem.mediaUploadState`.
///
/// It sits in its own file because the conformance file is past the length
/// limit. The conformance itself is declared in `MatrixRustSDK+Extensions`;
/// this member replaces the protocol's `nil` default for SDK items.
public extension MatrixRustSDK.EventTimelineItem {
    /// Upload state read off the SDK's send state.
    ///
    /// The same field the failed-send Discard UI reads (`localSendState`),
    /// read the same way: `.notSentYet(progress: nil)` is an echo that waits
    /// in the send queue, `.notSentYet(progress: value)` is an upload that
    /// runs. Sent, failed, and remote items have no upload state.
    ///
    /// Not part of the height fingerprint, on purpose: the indicator is an
    /// overlay, so a progress tick cannot move the row's height.
    var mediaUploadState: Models.MediaUploadState? {
        guard case let .notSentYet(progress: progress) = localSendState else { return nil }
        guard let progress else { return .queued }
        return .uploading(
            Models.MediaUploadSample(
                index: progress.index,
                current: progress.progress.current,
                total: progress.progress.total
            )
        )
    }
}
