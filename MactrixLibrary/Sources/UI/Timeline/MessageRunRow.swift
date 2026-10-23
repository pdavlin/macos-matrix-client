import Models
import SwiftUI
import Tokens

public extension TimelineGapBand {
    /// The points the band is worth (MATRIX-68).
    var spacing: CGFloat {
        switch self {
        case .none:
            return RhythmToken.noGap
        case .sameSenderBurst:
            return RhythmToken.sameSenderBurstGap
        case .senderTurn:
            return RhythmToken.senderTurnGap
        case .shortPause:
            return RhythmToken.shortPauseGap
        case .pause:
            return RhythmToken.pauseGap
        case .longPause:
            return RhythmToken.longPauseGap
        }
    }
}

/// One message row laid out by its place in a run (MATRIX-68): the profile
/// header on the first message only, and the rhythm gap above the row.
///
/// The flat layout keeps one column grid for every row. A continuation row
/// draws no header, and its body's leading column (the timestamp column plus
/// the row inset) is exactly as wide as the header's avatar column, so the
/// body text of every row in the run starts on the same x.
///
/// The gap is padding *outside* the body's hover and focus background, so the
/// highlight keeps its inset and the rhythm sits between highlights.
public struct MessageRunRow<Header: View, Message: View>: View {
    let grouping: TimelineRowGrouping
    let header: Header
    let message: Message

    public init(
        grouping: TimelineRowGrouping,
        @ViewBuilder header: () -> Header,
        @ViewBuilder message: () -> Message
    ) {
        self.grouping = grouping
        self.header = header()
        self.message = message()
    }

    public var body: some View {
        VStack(spacing: 0) {
            if grouping.showsProfileHeader {
                header
            }
            message
        }
        .padding(.top, grouping.gap.spacing)
    }
}
