#if canImport(AppKit)
    import AppKit
#endif
import Models
import SwiftUI
import Tokens

/// The click target that selects whole messages (MATRIX-113, M2-B6, D-2).
///
/// It lies over the timestamp column of a message, for the full height of
/// the message body, and is clear. A click there selects the message; with
/// Shift it extends the selection, with Command it toggles the message. The
/// message text, its links, and its media are outside the gutter, so a click
/// on them works as before: text selection stays character selection.
///
/// `MessageMainBody` puts it in an overlay, which never sizes the row, so the
/// gutter does not change a measured height (MATRIX-63).
struct MessageSelectionGutter: View {
    let select: @MainActor (MessageSelectionGesture) -> Void

    var body: some View {
        Color.clear
            .frame(width: DensityToken.timestampColumnWidth)
            .contentShape(Rectangle())
            .onTapGesture {
                select(Self.currentGesture)
            }
    }

    /// The gesture for the modifier keys that are down now. iOS has no
    /// gutter, so it always reads a plain click.
    static var currentGesture: MessageSelectionGesture {
        #if canImport(AppKit)
            let flags = NSEvent.modifierFlags
            return MessageSelectionGesture(isShiftDown: flags.contains(.shift), isCommandDown: flags.contains(.command))
        #else
            return .select
        #endif
    }
}
