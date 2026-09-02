import Models
import SwiftUI
import Tokens

public struct VirtualItemView: View {
    @Environment(\.colorScheme) var colorScheme
    let item: VirtualTimelineItem

    public init(item: VirtualTimelineItem) {
        self.item = item
    }

    func formatDate(_ date: Date) -> String {
        let dayInSecs: Double = 60 * 60 * 24
        if Date.now.timeIntervalSince(date).isLess(than: dayInSecs) {
            return String(localized: "Today")
        } else if Date.now.timeIntervalSince(date).isLess(than: dayInSecs * 2) {
            return String(localized: "Yesterday")
        } else {
            return date.formatted(date: .long, time: .omitted)
        }
    }

    public var body: some View {
        switch item {
        case let .dateDivider(date):
            Divider()
                .overlay {
                    Text(formatDate(date))
                        .padding(.horizontal, DensityToken.dividerHorizontalPadding)
                        .background(Color(NSColor.controlBackgroundColor))
                }
                .frame(height: DensityToken.dividerHeight)
                .padding(.horizontal, DensityToken.dividerHorizontalPadding)
        case .readMarker:
            Divider()
                .overlay {
                    Text("Read Marker")
                        .fontWeight(.medium)
                        .padding(.horizontal, DensityToken.dividerHorizontalPadding)
                        .background(Color(NSColor.controlBackgroundColor))
                }
                .frame(height: DensityToken.dividerHeight)
                .padding(.horizontal, DensityToken.dividerHorizontalPadding)
                .foregroundStyle(.red.mix(with: colorScheme == .light ? .black : .white, by: 0.1))
        case .timelineStart:
            Divider()
                .overlay {
                    Text("Start of conversation")
                        .fontWeight(.medium)
                        .padding(.horizontal, DensityToken.dividerHorizontalPadding)
                        .background(Color(NSColor.controlBackgroundColor))
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
    .background(Color(NSColor.controlBackgroundColor))
}
