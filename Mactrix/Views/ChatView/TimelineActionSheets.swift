import Core
import SwiftUI
import UI

/// The sheets that one room timeline's message actions open: the delete
/// confirmation and its failure alert (MATRIX-110), and the forward sheets
/// (MATRIX-112).
///
/// The requests live on the timeline, not in a row, because a row can
/// scroll away while a sheet is open. A room view adds this once for its
/// timeline. A merged chat (MATRIX-142 Wave 2) adds it once per member
/// timeline, because each row acts on its own member's timeline.
struct TimelineActionSheets: ViewModifier {
    @Bindable var timeline: LiveTimeline

    func body(content: Content) -> some View {
        content
            // Delete confirmation (MATRIX-110). The row or the Edit menu sets
            // the request; the sheet hands the reason back to the timeline.
            .sheet(item: $timeline.pendingRedaction) { request in
                UI.MessageRedactionSheet(
                    isOwn: request.isOwn,
                    onDelete: { reason in timeline.confirmRedaction(request, reason: reason) },
                    onCancel: { timeline.cancelRedaction() }
                )
            }
            .alert(
                "Could not delete the message",
                isPresented: Binding(
                    get: { timeline.redactionFailure != nil },
                    set: { if !$0 { timeline.redactionFailure = nil } }
                ),
                presenting: timeline.redactionFailure
            ) { _ in
                Button("OK") { timeline.redactionFailure = nil }
            } message: { failure in
                Text(failure)
            }
            .messageForwardSheets(timeline: timeline)
    }
}

extension View {
    /// Adds the message action sheets of `timeline` (MATRIX-110,
    /// MATRIX-112).
    func timelineActionSheets(timeline: LiveTimeline) -> some View {
        modifier(TimelineActionSheets(timeline: timeline))
    }
}
