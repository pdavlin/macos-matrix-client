import CoreGraphics
import Foundation
import Testing
@testable import TimelineSpikeApp
import TimelineSpikeCore

/// Deterministic stand-in for Core Text, so the arithmetic can be checked by hand.
///
/// Line heights are the ones the real measurer produces for the system font at 13pt and 11pt,
/// rounded up. Wrapping is 10pt per character, which makes the expected line counts obvious.
struct StubMeasurer: SpikeTextMeasuring {
    var pointsPerCharacter: CGFloat = 10

    func lineHeight(for role: SpikeFontRole) -> CGFloat {
        switch role {
        case .body, .header: return 16
        case .meta: return 14
        }
    }

    func lineCount(of text: String, role _: SpikeFontRole, width: CGFloat) -> Int {
        guard !text.isEmpty else { return 1 }
        let perLine = max(1, Int(width / pointsPerCharacter))
        return max(1, Int(ceil(Double(text.count) / Double(perLine))))
    }
}

@Suite("Row height model")
struct SpikeRowHeightModelTests {
    private let model = SpikeRowHeightModel(measurer: StubMeasurer())
    /// Wraps the text column at exactly 200pt: 288 - 16 - 16 - 32 - 12 - 12.
    private let rowWidth: CGFloat = 288

    private func item(
        content: EventContent,
        startsSenderRun: Bool = true,
        daySeparator: Date? = nil,
        reactions: [Reaction] = [],
        editCount: Int = 0
    ) -> TimelineItem {
        let event = SpikeEvent(
            id: EventID(7),
            sender: SpikeSender.roster[0],
            timestamp: Date(timeIntervalSince1970: 1_735_689_600),
            content: content,
            reactions: reactions,
            editCount: editCount
        )
        return TimelineItem(
            event: event,
            startsSenderRun: startsSenderRun,
            daySeparator: daySeparator
        )
    }

    private func text(_ characters: Int) -> EventContent {
        .text(TextBody(paragraphs: [String(repeating: "a", count: characters)], lineCount: 1))
    }

    @Test("The text column pays the stack's gap twice: once for the avatar, once for the spacer")
    func columnWidth() {
        #expect(SpikeRowHeightModel.contentColumnWidth(rowWidth: 288) == 200)
        #expect(SpikeRowHeightModel.contentColumnWidth(rowWidth: 1080) == 992)
        #expect(SpikeRowHeightModel.contentColumnWidth(rowWidth: 100) == 40)
    }

    @Test("Images are sized by the row's own width helper, one gap wider than the text")
    func imageWidth() {
        // SpikeRowView.imageWidth counts a single gap. The model reproduces that rather than
        // correcting it, because the height has to match the pixels on screen.
        #expect(SpikeRowHeightModel.imageAvailableWidth(rowWidth: 288) == 212)
        #expect(SpikeRowHeightModel.imageAvailableWidth(rowWidth: 1080) == 1004)
        #expect(SpikeRowHeightModel.imageAvailableWidth(rowWidth: 100) == 120)
    }

    @Test("A one-line message that opens a sender run is header plus body plus padding")
    func headerRow() {
        // header 16 + gap 2 + body 16 = 34, which is taller than the 32pt avatar, plus 4pt of
        // padding top and bottom.
        #expect(model.height(for: item(content: text(10)), rowWidth: rowWidth) == 42)
    }

    @Test("A continuation row drops the header and the avatar")
    func continuationRow() {
        let continuation = item(content: text(10), startsSenderRun: false)
        #expect(model.height(for: continuation, rowWidth: rowWidth) == 24)
    }

    @Test("A row that opens a run is never shorter than its avatar")
    func avatarSetsTheFloor() {
        let shortest = model.height(for: item(content: text(1)), rowWidth: rowWidth)
        #expect(shortest >= SpikeRowMetrics.avatarSize + 2 * SpikeRowMetrics.verticalPadding)
    }

    @Test("Wrapping is measured at the column width, not the row width")
    func wrapping() {
        // 60 characters at 20 per line is three lines: 16 + 2 + 48 = 66, plus 8 of padding.
        #expect(model.height(for: item(content: text(60)), rowWidth: rowWidth) == 74)
    }

    @Test("A day separator adds its fixed band")
    func daySeparator() {
        let day = Date(timeIntervalSince1970: 1_735_689_600)
        let plain = model.height(for: item(content: text(10)), rowWidth: rowWidth)
        let separated = model.height(
            for: item(content: text(10), daySeparator: day),
            rowWidth: rowWidth
        )
        #expect(separated - plain == SpikeRowMetrics.daySeparatorHeight)
    }

    @Test("A reaction row adds a chip line, its padding and its top gap")
    func reactions() {
        let plain = model.height(for: item(content: text(10)), rowWidth: rowWidth)
        let reacted = model.height(
            for: item(content: text(10), reactions: [Reaction(key: "👍", count: 2)]),
            rowWidth: rowWidth
        )
        // 2pt stack spacing + 4pt top gap + 14pt line + 4pt chip padding.
        #expect(reacted - plain == 24)
    }

    @Test("A second reaction key does not add a second line")
    func reactionsStayOnOneLine() {
        let one = model.height(
            for: item(content: text(10), reactions: [Reaction(key: "👍", count: 2)]),
            rowWidth: rowWidth
        )
        let three = model.height(
            for: item(
                content: text(10),
                reactions: [
                    Reaction(key: "👍", count: 2),
                    Reaction(key: "🎉", count: 1),
                    Reaction(key: "🚀", count: 4)
                ]
            ),
            rowWidth: rowWidth
        )
        #expect(one == three)
    }

    @Test("The edit marker is another child of the content stack")
    func editMarker() {
        let plain = model.height(for: item(content: text(10)), rowWidth: rowWidth)
        let edited = model.height(
            for: item(content: text(10), editCount: 3),
            rowWidth: rowWidth
        )
        // 6pt stack spacing plus a 14pt meta line.
        #expect(edited - plain == 20)
    }

    @Test("Paragraphs stack at 6pt")
    func paragraphSpacing() {
        let single = model.height(for: item(content: text(10)), rowWidth: rowWidth)
        let body = TextBody(paragraphs: ["aaaa", "bbbb", "cccc"], lineCount: 3)
        let triple = model.height(for: item(content: .text(body)), rowWidth: rowWidth)
        // Two more lines at 16 and two 6pt gaps.
        #expect(triple - single == 44)
    }

    @Test("An image row is the clamped placeholder plus its caption")
    func imageRow() {
        let placeholder = ImagePlaceholder(
            aspectRatio: 1.5,
            intrinsicWidth: 300,
            hue: 0.2,
            caption: nil
        )
        let size = SpikeRowMetrics.imageSize(
            for: placeholder,
            availableWidth: SpikeRowHeightModel.imageAvailableWidth(rowWidth: rowWidth)
        )
        let bare = model.height(for: item(content: .image(placeholder)), rowWidth: rowWidth)
        // header 16 + gap 2 + image, plus 8 of padding, rounded up.
        #expect(bare == ceil(16 + 2 + size.height + 8))

        let captioned = ImagePlaceholder(
            aspectRatio: 1.5,
            intrinsicWidth: 300,
            hue: 0.2,
            caption: "a caption"
        )
        let withCaption = model.height(for: item(content: .image(captioned)), rowWidth: rowWidth)
        // 4pt gap plus one 14pt meta line.
        #expect(withCaption - bare == 18)
    }

    @Test("Heights are whole points, so the document height cannot drift by rounding")
    func heightsAreIntegral() {
        let placeholder = ImagePlaceholder(
            aspectRatio: 1.37,
            intrinsicWidth: 331,
            hue: 0.4,
            caption: "odd size"
        )
        let height = model.height(for: item(content: .image(placeholder)), rowWidth: 1004)
        #expect(height == height.rounded(.down))
    }
}

@Suite("Core Text measurer")
struct CoreTextSpikeMeasurerTests {
    private let measurer = CoreTextSpikeMeasurer()

    @Test("Line heights are whole points and ordered by font size")
    func lineHeights() {
        let body = measurer.lineHeight(for: .body)
        let header = measurer.lineHeight(for: .header)
        let meta = measurer.lineHeight(for: .meta)
        #expect(body > 0)
        #expect(body == body.rounded(.down))
        #expect(meta < body)
        #expect(header >= body)
    }

    @Test("Text wraps into more lines as the column narrows")
    func wrapping() {
        let sentence = String(repeating: "the quick brown fox ", count: 12)
        let wide = measurer.lineCount(of: sentence, role: .body, width: 800)
        let narrow = measurer.lineCount(of: sentence, role: .body, width: 200)
        #expect(wide >= 1)
        #expect(narrow > wide)
    }

    @Test("An empty string still occupies one line")
    func emptyString() {
        #expect(measurer.lineCount(of: "", role: .body, width: 400) == 1)
    }

    @Test("Measurement is deterministic")
    func determinism() {
        let sentence = String(repeating: "bridge relay backfill ", count: 7)
        let first = measurer.lineCount(of: sentence, role: .body, width: 317)
        let second = measurer.lineCount(of: sentence, role: .body, width: 317)
        #expect(first == second)
    }

    @Test("The whole corpus measures without a zero or a NaN, and the cost is reported")
    func measuresTheCorpus() {
        let generator = SyntheticEventGenerator(seed: HarnessConfiguration.default.seed)
        let events = generator.events(in: 0 ..< 10_000)
        let items = events.map { TimelineItem(event: $0) }
        let model = SpikeRowHeightModel(measurer: CoreTextSpikeMeasurer())

        let started = Date()
        var total: CGFloat = 0
        var shortest = CGFloat.greatestFiniteMagnitude
        for item in items {
            let height = model.height(for: item, rowWidth: 1004)
            total += height
            shortest = min(shortest, height)
        }
        let elapsed = Date().timeIntervalSince(started) * 1000

        #expect(total.isFinite)
        #expect(shortest >= SpikeRowMetrics.avatarSize)
        print(
            "[S-14] measured \(items.count) rows in " + String(format: "%.0f", elapsed)
                + " ms, mean row " + String(format: "%.1f", total / CGFloat(items.count)) + " pt"
        )
    }
}
