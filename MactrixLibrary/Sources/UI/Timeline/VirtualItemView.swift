import Models
import SwiftUI
import Tokens

public struct VirtualItemView: View {
    let item: VirtualTimelineItem

    public init(item: VirtualTimelineItem) {
        self.item = item
    }

    public var body: some View {
        switch item {
        case let .dateDivider(date):
            // MATRIX-136: a day pill over a separator line.
            DayDividerRow(date: date)
        case .readMarker:
            // MATRIX-136: the "New" divider, with its glow and dim.
            NewDividerRow()
        case .timelineStart:
            Divider()
                .overlay {
                    Text("Start of conversation")
                        .fontWeight(.medium)
                        .padding(.horizontal, DensityToken.dividerHorizontalPadding)
                        .background(Color(PlatformColor.controlBackgroundColor))
                }
                .frame(height: DensityToken.dividerHeight)
                .padding(.horizontal, DensityToken.dividerHorizontalPadding)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        VirtualItemView(item: .timelineStart)
        VirtualItemView(item: .dateDivider(date: Date()))
        VirtualItemView(item: .readMarker)
    }
    .frame(width: 400)
    .background(Color(PlatformColor.controlBackgroundColor))
}
