import AppKit
import CoreText
import Foundation
import TimelineSpikeCore

/// The three fonts `SpikeRowView` uses, named so the height model and the text measurer
/// cannot disagree about which one applies to a block.
enum SpikeFontRole: Hashable, CaseIterable {
    /// `SpikeRowMetrics.bodyFont` — message paragraphs.
    case body
    /// `SpikeRowMetrics.headerFont` — the sender name.
    case header
    /// `SpikeRowMetrics.metaFont` — timestamps, captions, reaction chips, edit markers.
    case meta

    var nsFont: NSFont {
        switch self {
        case .body:
            return .systemFont(ofSize: SpikeRowMetrics.bodyFontSize)
        case .header:
            return .systemFont(ofSize: SpikeRowMetrics.headerFontSize, weight: .semibold)
        case .meta:
            return .systemFont(ofSize: SpikeRowMetrics.metaFontSize)
        }
    }
}

/// Line-box measurement, factored out so the arithmetic in `SpikeRowHeightModel` can be
/// unit-tested against a stub instead of against the text engine.
protocol SpikeTextMeasuring {
    /// Height of one line box, in whole points.
    func lineHeight(for role: SpikeFontRole) -> CGFloat
    /// Number of line boxes `text` occupies when wrapped at `width`.
    func lineCount(of text: String, role: SpikeFontRole, width: CGFloat) -> Int
}

/// Core Text line breaking, which is the same typesetter SwiftUI's `Text` uses.
///
/// ## Why not measure the SwiftUI view itself
///
/// The exact answer would be to build an `NSHostingView` per row and read its fitting size.
/// That costs a full SwiftUI layout pass per row, and the table needs every row's height up
/// front to know its document height, so a 10k timeline would pay 10k hosting layouts before
/// the first frame. Core Text line counting is the same measurement without the view graph.
///
/// ## Rounding
///
/// Line heights are rounded **up** to whole points, and the finished row height is rounded up
/// again. The bias is deliberate and one-directional: a row that is a fraction of a point too
/// tall shows a hair of extra space, while a row that is too short clips the last line of
/// text. Set `TIMELINE_SPIKE_HEIGHT_AUDIT=1` to have the renderer compare these numbers
/// against real SwiftUI layout for the rows it displays.
final class CoreTextSpikeMeasurer: SpikeTextMeasuring {
    private var lineHeights: [SpikeFontRole: CGFloat] = [:]

    init() {
        for role in SpikeFontRole.allCases {
            lineHeights[role] = Self.lineHeight(of: role.nsFont)
        }
    }

    /// SwiftUI's line box, which is **not** `ceil(ascent + descent + leading)`.
    ///
    /// Each metric is rounded up on its own. At 13pt that is `13 + 3 = 16` either way, so the
    /// difference hides; at 11pt it is `11 + 3 = 14` against a combined `ceil(12.95) = 13`,
    /// and a row with a caption, an edit marker and a reaction chip then comes out three
    /// points short and clips. Both forms are checked against real SwiftUI layout in
    /// `HeightModelFidelityTests`.
    static func lineHeight(of font: NSFont) -> CGFloat {
        ceil(font.ascender) + ceil(-font.descender) + ceil(font.leading)
    }

    func lineHeight(for role: SpikeFontRole) -> CGFloat {
        lineHeights[role] ?? Self.lineHeight(of: role.nsFont)
    }

    func lineCount(of text: String, role: SpikeFontRole, width: CGFloat) -> Int {
        guard !text.isEmpty else { return 1 }
        let attributed = NSAttributedString(string: text, attributes: [.font: role.nsFont])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let length = attributed.length
        let constraint = Double(max(1, width))
        var start = 0
        var lines = 0
        while start < length {
            let consumed = CTTypesetterSuggestLineBreak(typesetter, start, constraint)
            guard consumed > 0 else { break }
            start += consumed
            lines += 1
        }
        return max(1, lines)
    }
}

/// Reproduces `SpikeRowView`'s layout arithmetic so `NSTableView` can be told a row's height
/// before that row is ever built.
///
/// Every constant here comes from `SpikeRowMetrics`; nothing is invented. The structure
/// mirrors the view one block at a time, because the only way this stays correct is by being
/// readable next to `SpikeRowView.body`.
struct SpikeRowHeightModel {
    let measurer: SpikeTextMeasuring

    init(measurer: SpikeTextMeasuring) {
        self.measurer = measurer
    }

    /// The width the paragraphs wrap at.
    ///
    /// `SpikeRowView`'s `HStack` holds three children — the avatar, the text column and a
    /// trailing `Spacer(minLength: 0)` — and the stack's 12pt spacing applies between each
    /// adjacent pair. So the text column pays the gap **twice**, not once, and is 12pt
    /// narrower than the row's own `imageWidth` helper suggests. That 12pt is enough to move a
    /// line break, which is a whole 16pt line of height, so it is not a rounding detail:
    /// getting it wrong clips text. Measured against SwiftUI's own layout in
    /// `HeightModelFidelityTests`.
    static func contentColumnWidth(rowWidth: CGFloat) -> CGFloat {
        max(
            40,
            rowWidth
                - 2 * SpikeRowMetrics.horizontalPadding
                - SpikeRowMetrics.avatarSize
                - 2 * SpikeRowMetrics.avatarTextGap
        )
    }

    /// The width `SpikeRowView` hands to `SpikeRowMetrics.imageSize(for:availableWidth:)`.
    ///
    /// The row computes this itself, one gap short of the width the column really gets. It is
    /// reproduced exactly, mistake included: the modelled height has to match what the view
    /// draws, not what the view should have drawn.
    static func imageAvailableWidth(rowWidth: CGFloat) -> CGFloat {
        max(
            120,
            rowWidth
                - 2 * SpikeRowMetrics.horizontalPadding
                - SpikeRowMetrics.avatarSize
                - SpikeRowMetrics.avatarTextGap
        )
    }

    /// Height of one row, in whole points.
    func height(for item: TimelineItem, rowWidth: CGFloat) -> CGFloat {
        let columnWidth = Self.contentColumnWidth(rowWidth: rowWidth)

        // The text column: an optional header, the content, and an optional reaction row,
        // separated by `headerBodyGap`.
        var blocks: [CGFloat] = []
        if item.startsSenderRun {
            blocks.append(headerHeight)
        }
        blocks.append(
            contentHeight(for: item.event, columnWidth: columnWidth, rowWidth: rowWidth)
        )
        if !item.event.reactions.isEmpty {
            blocks.append(reactionRowHeight)
        }
        let columnHeight = blocks.reduce(0, +)
            + CGFloat(max(0, blocks.count - 1)) * SpikeRowMetrics.headerBodyGap

        // The avatar column is 32pt when the row opens a sender run and a 1pt spacer
        // otherwise, and the `HStack` is as tall as its tallest column.
        let avatarHeight: CGFloat = item.startsSenderRun ? SpikeRowMetrics.avatarSize : 1

        var total = max(columnHeight, avatarHeight) + 2 * SpikeRowMetrics.verticalPadding
        if item.daySeparator != nil {
            total += SpikeRowMetrics.daySeparatorHeight
        }
        return ceil(total)
    }

    // MARK: - Blocks

    /// The header `HStack` is as tall as the taller of the name and the timestamp.
    private var headerHeight: CGFloat {
        max(measurer.lineHeight(for: .header), measurer.lineHeight(for: .meta))
    }

    /// One chip: a meta-font line plus its 2pt vertical padding, plus the row's 4pt top gap.
    private var reactionRowHeight: CGFloat {
        measurer.lineHeight(for: .meta) + 4 + SpikeRowMetrics.reactionTopGap
    }

    private func contentHeight(
        for event: SpikeEvent,
        columnWidth: CGFloat,
        rowWidth: CGFloat
    ) -> CGFloat {
        switch event.content {
        case .text(let body):
            return textContentHeight(body: body, editCount: event.editCount, columnWidth: columnWidth)
        case .image(let placeholder):
            return imageContentHeight(
                placeholder: placeholder,
                columnWidth: columnWidth,
                rowWidth: rowWidth
            )
        }
    }

    /// Paragraphs stacked at 6pt, with the edit marker as one more child of the same stack.
    private func textContentHeight(
        body: TextBody,
        editCount: Int,
        columnWidth: CGFloat
    ) -> CGFloat {
        let bodyLineHeight = measurer.lineHeight(for: .body)
        var height: CGFloat = 0
        for paragraph in body.paragraphs {
            let lines = measurer.lineCount(of: paragraph, role: .body, width: columnWidth)
            height += CGFloat(lines) * bodyLineHeight
        }
        var childCount = body.paragraphs.count
        if editCount > 0 {
            height += measurer.lineHeight(for: .meta)
            childCount += 1
        }
        return height + CGFloat(max(0, childCount - 1)) * 6
    }

    /// The placeholder shape at its clamped size, plus a wrapped caption at 4pt.
    private func imageContentHeight(
        placeholder: ImagePlaceholder,
        columnWidth: CGFloat,
        rowWidth: CGFloat
    ) -> CGFloat {
        var height = SpikeRowMetrics.imageSize(
            for: placeholder,
            availableWidth: Self.imageAvailableWidth(rowWidth: rowWidth)
        ).height
        if let caption = placeholder.caption {
            let lines = measurer.lineCount(of: caption, role: .meta, width: columnWidth)
            height += 4 + CGFloat(lines) * measurer.lineHeight(for: .meta)
        }
        return height
    }
}
