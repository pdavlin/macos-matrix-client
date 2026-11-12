import Core
import Models
import SwiftUI
import Tokens
import UI

// MARK: - Merged chat (MATRIX-143 Phase B)

/// The parts of the composer that only a merged chat has. Each one is a
/// no-op, or the room behaviour, when `merged` is nil.
///
/// The target picker sits in the composer's top accessory row, where the
/// reply and the edit bars go (orchestrator decision, MATRIX-143 Phase B).
/// For a new message it is a menu on its own row. During a reply or an edit
/// the message must go to the event's room, so the picker is a plain label
/// beside that bar (`ComposerTargetPicker` with reason `.reply` or `.edit`).
extension ChatInputView {
    /// The target picker on its own row, for a new message. Nothing for a
    /// room's composer.
    @ViewBuilder var mergedTargetRow: some View {
        if let merged, let target = merged.composerTarget {
            HStack(spacing: 0) {
                targetPicker(merged, target: target)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DensityToken.rowHorizontalPadding)
            .padding(.top, DensityToken.rowVerticalPadding * 2)
        }
    }

    /// The reply or edit bar, with the target as a plain label beside it in
    /// a merged chat.
    @ViewBuilder func besideMergedTarget(@ViewBuilder _ bar: () -> some View) -> some View {
        if let merged, let target = merged.composerTarget {
            HStack(alignment: .center, spacing: 0) {
                targetPicker(merged, target: target)
                    .padding(.leading, DensityToken.rowHorizontalPadding)
                bar()
            }
        } else {
            bar()
        }
    }

    private func targetPicker(_ merged: MergedComposerSession, target: MergedSendTarget) -> some View {
        UI.ComposerTargetPicker(
            options: merged.targetOptions,
            selectedRoomId: target.roomId,
            reason: target.reason,
            onSelect: { merged.pick($0) }
        )
        .environment(\.chatBadgeImageLoader, appState.matrixClient)
    }

    /// Scrolls the timeline to the newest row after a send: the merged
    /// timeline for a merged chat, whose member timeline has no container.
    func scrollToNewestAfterSend() {
        if let merged {
            merged.requestScrollToBottom()
        } else {
            timeline.requestScrollToBottom()
        }
    }
}
