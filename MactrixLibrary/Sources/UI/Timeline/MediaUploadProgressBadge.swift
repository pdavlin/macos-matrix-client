import Models
import SwiftUI
import Tokens

/// Upload indicator for an own media local echo (MATRIX-107): a progress
/// ring, the percent uploaded, and a cancel control.
///
/// Presentational only. The SDK's send queue owns the upload; the app target
/// maps its send state into `MediaUploadState` and wires `cancel` to the
/// media send cancel call.
///
/// Draw it with `mediaUploadOverlay(_:placement:cancel:)`, never in the
/// layout: the overlay is what keeps every progress tick height-neutral, and
/// the row's height fingerprint relies on that.
public struct MediaUploadProgressBadge: View {
    let state: MediaUploadState
    let cancel: () -> Void

    @Environment(\.timelineTypography) private var typography

    /// - Parameters:
    ///   - state: what the indicator shows. `.queued` and an upload without a
    ///     total draw an indeterminate ring.
    ///   - cancel: called when the person clicks the cancel control.
    public init(state: MediaUploadState, cancel: @escaping () -> Void) {
        self.state = state
        self.cancel = cancel
    }

    public var body: some View {
        HStack(spacing: DensityToken.uploadBadgeSpacing) {
            ring
            label
                .monospacedDigit()
                .fixedSize()
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .help(Text("Cancel upload"))
            .accessibilityLabel(Text("Cancel upload"))
        }
        .font(.system(size: typography.footnote))
        .padding(.horizontal, DensityToken.uploadBadgeHorizontalPadding)
        .padding(.vertical, DensityToken.uploadBadgeVerticalPadding)
        // Opaque, not glass: the badge sits on scrollable timeline content
        // (CLAUDE.md hard rule 2).
        .background(.background, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: BubbleToken.hoverBorderWidth))
        .accessibilityElement(children: .contain)
    }

    /// Determinate ring when the SDK reports a total, a spinner otherwise.
    @ViewBuilder
    private var ring: some View {
        if let fraction = state.fraction {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: DensityToken.uploadRingLineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: DensityToken.uploadRingLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: DensityToken.uploadRingDiameter, height: DensityToken.uploadRingDiameter)
            .accessibilityHidden(true)
        } else {
            ProgressView()
                .controlSize(.mini)
                .frame(width: DensityToken.uploadRingDiameter, height: DensityToken.uploadRingDiameter)
                .accessibilityHidden(true)
        }
    }

    /// The percent uploaded, or what the echo waits for.
    @ViewBuilder
    private var label: some View {
        if let percent = state.percent {
            // Whole percent from the model (rounded down), formatted for the
            // locale. Dividing a whole number by 100 is exact for the format.
            Text(Double(percent) / 100, format: .percent.precision(.fractionLength(0)))
                .accessibilityLabel(Text("Uploading, \(percent) percent"))
        } else if case .queued = state {
            Text("Queued")
                .accessibilityLabel(Text("Waiting to upload"))
        } else {
            Text("Uploading")
        }
    }
}

/// Where the upload badge sits on a media body.
public enum MediaUploadBadgePlacement: Sendable {
    /// Inside the top trailing corner of a visual media body (image, video).
    case mediaCorner
    /// At the trailing edge of the message column, centered on the body. For
    /// one-line bodies (file, audio, gallery) that a corner badge would cover.
    case rowTrailing
}

public extension View {
    /// Overlays the upload badge on a media body (MATRIX-107).
    ///
    /// Never changes the body's height, in any state: the badge is an
    /// overlay, and `.rowTrailing` only widens the body to the width its
    /// column already proposes. The modifier is applied the same way whether
    /// or not an upload runs, so the view tree does not change shape when the
    /// upload starts or ends.
    ///
    /// - Parameters:
    ///   - state: the upload state, or nil for no badge.
    ///   - placement: where the badge sits.
    ///   - cancel: called when the person clicks the cancel control.
    func mediaUploadOverlay(
        _ state: MediaUploadState?,
        placement: MediaUploadBadgePlacement,
        cancel: @escaping () -> Void
    ) -> some View {
        modifier(MediaUploadOverlayModifier(state: state, placement: placement, cancel: cancel))
    }
}

/// The overlay behind `mediaUploadOverlay(_:placement:cancel:)`.
struct MediaUploadOverlayModifier: ViewModifier {
    let state: MediaUploadState?
    let placement: MediaUploadBadgePlacement
    let cancel: () -> Void

    func body(content: Content) -> some View {
        switch placement {
        case .mediaCorner:
            content.overlay(alignment: .topTrailing) {
                badge.padding(DensityToken.uploadBadgeInset)
            }
        case .rowTrailing:
            // The frame takes the width the message column proposes and hands
            // the same proposal to the body, so the body wraps exactly as it
            // did, and the frame reports the body's height.
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) { badge }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let state {
            MediaUploadProgressBadge(state: state, cancel: cancel)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        MediaUploadProgressBadge(state: .queued, cancel: {})
        MediaUploadProgressBadge(state: .uploading(.init(index: 1, current: 42, total: 100)), cancel: {})
        RoundedRectangle(cornerRadius: BubbleToken.mediaCornerRadius)
            .fill(Color.gray.opacity(0.4))
            .frame(width: 240, height: 160)
            .mediaUploadOverlay(
                .uploading(.init(index: 0, current: 7, total: 10)),
                placement: .mediaCorner,
                cancel: {}
            )
    }
    .padding()
}
