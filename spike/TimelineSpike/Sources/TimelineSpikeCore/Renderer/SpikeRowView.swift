import SwiftUI

/// The shared SwiftUI row.
///
/// Every SwiftUI candidate renders this so the measured workload per row is identical. It
/// is intentionally plain: no glass, no animation, no gradients. Chrome would add cost that
/// tells us nothing about list architecture, and the contract forbids glass on scrollable
/// content anyway.
public struct SpikeRowView: View {
    private let item: TimelineItem
    private let contentWidth: CGFloat

    public init(item: TimelineItem, contentWidth: CGFloat) {
        self.item = item
        self.contentWidth = contentWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let day = item.daySeparator {
                daySeparator(day)
            }
            HStack(alignment: .top, spacing: SpikeRowMetrics.avatarTextGap) {
                avatarColumn
                VStack(alignment: .leading, spacing: SpikeRowMetrics.headerBodyGap) {
                    if item.startsSenderRun {
                        header
                    }
                    content
                    if !item.event.reactions.isEmpty {
                        reactionRow
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SpikeRowMetrics.horizontalPadding)
            .padding(.vertical, SpikeRowMetrics.verticalPadding)
        }
    }

    @ViewBuilder
    private var avatarColumn: some View {
        if item.startsSenderRun {
            Circle()
                .fill(SpikeRowMetrics.color(forHue: item.event.sender.avatarHue))
                .frame(width: SpikeRowMetrics.avatarSize, height: SpikeRowMetrics.avatarSize)
        } else {
            Color.clear
                .frame(width: SpikeRowMetrics.avatarSize, height: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(item.event.sender.displayName)
                .font(SpikeRowMetrics.headerFont)
            Text(SpikeRowMetrics.timeLabel(for: item.event.timestamp))
                .font(SpikeRowMetrics.metaFont)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.event.content {
        case .text(let body):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(body.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(SpikeRowMetrics.bodyFont)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if item.event.editCount > 0 {
                    Text("edited \(item.event.editCount)x")
                        .font(SpikeRowMetrics.metaFont)
                        .foregroundStyle(.tertiary)
                }
            }
        case .image(let placeholder):
            let size = SpikeRowMetrics.imageSize(for: placeholder, availableWidth: imageWidth)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SpikeRowMetrics.color(forHue: placeholder.hue))
                    .frame(width: size.width, height: size.height)
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(Int(size.width))x\(Int(size.height))")
                            .font(SpikeRowMetrics.metaFont)
                            .padding(4)
                            .foregroundStyle(.white)
                    }
                if let caption = placeholder.caption {
                    Text(caption)
                        .font(SpikeRowMetrics.metaFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var reactionRow: some View {
        HStack(spacing: 6) {
            ForEach(item.event.reactions) { reaction in
                Text("\(reaction.key) \(reaction.count)")
                    .font(SpikeRowMetrics.metaFont)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                    )
            }
        }
        .padding(.top, SpikeRowMetrics.reactionTopGap)
    }

    private func daySeparator(_ day: Date) -> some View {
        HStack(spacing: 8) {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text(SpikeRowMetrics.dayLabel(for: day))
                .font(SpikeRowMetrics.metaFont)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, SpikeRowMetrics.horizontalPadding)
        .frame(height: SpikeRowMetrics.daySeparatorHeight)
    }

    private var imageWidth: CGFloat {
        max(
            120,
            contentWidth
                - 2 * SpikeRowMetrics.horizontalPadding
                - SpikeRowMetrics.avatarSize
                - SpikeRowMetrics.avatarTextGap
        )
    }
}
