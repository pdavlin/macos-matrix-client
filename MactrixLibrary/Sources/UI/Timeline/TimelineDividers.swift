import Models
import SwiftUI
import Tokens

// MATRIX-136: the day pill, the floating sticky day pill, and the "New"
// divider. Every divider row keeps the fixed `DensityToken.dividerHeight`,
// so the row measurement does not change.

/// A centered capsule with the date of a day. Opaque, never glass: it sits
/// on the timeline.
///
/// MATRIX-157: the text comes from `Models.DayDividerLabel`, relative to
/// `CurrentDay.shared`. The body reads that observable day, so a pill on
/// screen changes its text when the day changes. Its height stays.
public struct DayDividerPill: View {
    @Environment(\.displayScale) private var displayScale
    let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        Text(CurrentDay.shared.dividerLabel(for: date))
            .font(.system(size: TimelineChromeToken.dayPillFontSize, weight: .semibold))
            .lineLimit(1)
            .padding(.vertical, TimelineChromeToken.dayPillVerticalPadding)
            .padding(.horizontal, TimelineChromeToken.dayPillHorizontalPadding)
            .background(Capsule().fill(Color(PlatformColor.windowBackgroundColor)))
            .overlay(Capsule().strokeBorder(Color(PlatformColor.separatorColor), lineWidth: 1 / displayScale))
            .compositingGroup()
            .shadow(
                color: .black.opacity(TimelineChromeToken.dayPillShadowOpacity),
                radius: TimelineChromeToken.dayPillShadowRadius,
                y: TimelineChromeToken.dayPillShadowOffsetY
            )
    }
}

/// The date divider row: a day pill over a separator line across the row.
struct DayDividerRow: View {
    let date: Date

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(PlatformColor.separatorColor))
                .frame(height: TimelineChromeToken.dayDividerLineThickness)
            DayDividerPill(date: date)
        }
        .frame(maxWidth: .infinity)
        .frame(height: DensityToken.dividerHeight)
        .padding(.horizontal, DensityToken.dividerHorizontalPadding)
    }
}

/// The floating copy of the day pill that the timeline container pins near
/// the top of the timeline while it scrolls.
///
/// It repeats what the date dividers already say, so it is hidden from
/// accessibility.
public struct StickyDayPill: View {
    let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        DayDividerPill(date: date)
            .padding(TimelineChromeToken.stickyDayPillShadowMargin)
            .accessibilityHidden(true)
    }
}

/// The read marker as a "New" divider: an accent label between two accent
/// lines.
///
/// When it first shows, it glows for `MotionToken.newDividerGlowDuration`.
/// After `MotionToken.newDividerDimDelay` it dims to
/// `MotionToken.newDividerDimmedOpacity`. With Reduce Motion both changes are
/// instant. Only opacity and a shadow change, never the row height.
public struct NewDividerRow: View {
    /// The look of the divider over time.
    public enum Phase: Sendable {
        /// Just shown: full opacity with the accent glow.
        case glowing
        /// The glow is gone, full opacity.
        case lit
        /// Dimmed after the delay.
        case dimmed
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .glowing
    private let fixedPhase: Phase?

    /// - Parameter phase: a fixed phase that never animates, for snapshots.
    ///   Nil runs the glow and the dim.
    public init(phase: Phase? = nil) {
        fixedPhase = phase
    }

    public var body: some View {
        let shown = fixedPhase ?? phase
        HStack(spacing: DensityToken.dividerHorizontalPadding) {
            line
            Text("New", comment: "The divider above the first unread message in a timeline.")
                .font(.system(size: TimelineChromeToken.newDividerFontSize, weight: .semibold).smallCaps())
                .lineLimit(1)
            line
        }
        .foregroundStyle(Color.accentColor)
        .shadow(
            color: Color.accentColor.opacity(shown == .glowing ? 1 : 0),
            radius: TimelineChromeToken.newDividerGlowRadius
        )
        .opacity(shown == .dimmed ? MotionToken.newDividerDimmedOpacity : 1)
        .frame(height: DensityToken.dividerHeight)
        .padding(.horizontal, DensityToken.dividerHorizontalPadding)
        .task(id: fixedPhase == nil) {
            guard fixedPhase == nil else { return }
            await runPhases()
        }
    }

    private var line: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: TimelineChromeToken.newDividerLineThickness)
    }

    /// Fades the glow out, waits, then dims. A recycled row view keeps its
    /// phase, so a dimmed divider does not glow again.
    private func runPhases() async {
        if phase == .glowing {
            let glowFade = MotionToken.standard(duration: MotionToken.newDividerGlowDuration)
            withAnimation(MotionToken.animation(glowFade, reduceMotion: reduceMotion)) {
                phase = .lit
            }
        }
        guard phase == .lit else { return }
        try? await Task.sleep(for: .seconds(MotionToken.newDividerDimDelay))
        guard !Task.isCancelled else { return }
        let dim = MotionToken.standard(duration: MotionToken.newDividerGlowDuration)
        withAnimation(MotionToken.animation(dim, reduceMotion: reduceMotion)) {
            phase = .dimmed
        }
    }
}
