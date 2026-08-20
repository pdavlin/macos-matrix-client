import Foundation

/// Produces the synthetic timeline.
///
/// ## Why an index line
///
/// Every event is a pure function of `(seed, index)`, where `index` runs over all of `Int`.
/// The initial window is `0 ..< initialEventCount`; back-pagination prepends
/// `-50 ..< 0`, then `-100 ..< -50`, and so on, without bound. That gives three properties
/// the harness needs:
///
/// - **Determinism.** Two runs with the same seed produce byte-identical timelines,
///   including everything a back-pagination driver prepends.
/// - **Locality.** Generating index `-3_000` costs the same as generating index `7`. No
///   prefix state, no warm-up.
/// - **Order.** `timestamp(at:)` is strictly increasing in `index` by construction, so a
///   prepended batch is always older than everything already loaded.
///
/// Randomised structure that needs continuity, notably sender runs, is generated per
/// fixed-size chunk. A run therefore never crosses a chunk boundary. That is invisible in
/// the rendered output: a run simply ends.
public struct SyntheticEventGenerator: Sendable {
    /// Indices per generation chunk. Sender runs restart at chunk boundaries.
    public static let chunkSize = 512

    /// Reference instant for `index == 0`. Fixed so timestamps do not depend on the clock.
    public static let epoch = Date(timeIntervalSince1970: 1_735_689_600)

    /// Nominal spacing between adjacent events, in seconds.
    private static let baseInterval: Double = 180

    /// Events per "waking period" before a long quiet gap is inserted.
    private static let eventsPerBurst = 220

    /// Length of the quiet gap, in seconds. `220 * 180 + 57_600` is about 27 hours, so a
    /// day separator lands roughly every 220 events.
    private static let burstGap: Double = 57_600

    public let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    // MARK: - Public generation

    /// The event at a single index.
    public func event(at index: Int) -> SpikeEvent {
        let chunkIndex = Self.floorDiv(index, Self.chunkSize)
        let chunk = makeChunk(chunkIndex)
        return chunk[index - chunkIndex * Self.chunkSize]
    }

    /// Every event in a half-open index range, in ascending order.
    public func events(in range: Range<Int>) -> [SpikeEvent] {
        guard !range.isEmpty else { return [] }
        let firstChunk = Self.floorDiv(range.lowerBound, Self.chunkSize)
        let lastChunk = Self.floorDiv(range.upperBound - 1, Self.chunkSize)
        var result: [SpikeEvent] = []
        result.reserveCapacity(range.count)
        for chunkIndex in firstChunk ... lastChunk {
            let start = chunkIndex * Self.chunkSize
            let chunk = makeChunk(chunkIndex)
            let lower = max(range.lowerBound, start) - start
            let upper = min(range.upperBound, start + Self.chunkSize) - start
            result.append(contentsOf: chunk[lower ..< upper])
        }
        return result
    }

    /// The timestamp for an index. Strictly increasing in `index`.
    public func timestamp(at index: Int) -> Date {
        var jitterSource = SplitMix64(seed: SplitMix64.derivedSeed(from: seed &+ 0x5EED, salt: index))
        let jitter = Double(jitterSource.int(in: 0 ..< 150))
        let offset = Double(index) * Self.baseInterval
            + Double(Self.floorDiv(index, Self.eventsPerBurst)) * Self.burstGap
            + jitter
        return Self.epoch.addingTimeInterval(offset)
    }

    /// Builds a text body with the requested target line count.
    ///
    /// Exposed so the mutation driver can grow and shrink an existing body using the same
    /// corpus and the same shape as the original.
    public func makeTextBody(lineCount: Int, using generator: inout SplitMix64) -> TextBody {
        let target = max(1, min(Self.maximumLineCount, lineCount))
        var paragraphs: [String] = []
        var remaining = target
        while remaining > 0 {
            let linesInParagraph = min(remaining, generator.int(in: 1 ... 6))
            var lines: [String] = []
            lines.reserveCapacity(linesInParagraph)
            for _ in 0 ..< linesInParagraph {
                let wordCount = generator.int(in: 6 ... 14)
                var words: [String] = []
                words.reserveCapacity(wordCount)
                for _ in 0 ..< wordCount {
                    words.append(generator.element(of: SpikeCorpus.words))
                }
                lines.append(words.joined(separator: " "))
            }
            paragraphs.append(lines.joined(separator: " "))
            remaining -= linesInParagraph
        }
        return TextBody(paragraphs: paragraphs, lineCount: target)
    }

    /// The largest target line count the generator or the mutation driver will author.
    public static let maximumLineCount = 40

    // MARK: - Chunk construction

    private func makeChunk(_ chunkIndex: Int) -> [SpikeEvent] {
        var generator = SplitMix64(seed: SplitMix64.derivedSeed(from: seed, salt: chunkIndex))
        let start = chunkIndex * Self.chunkSize
        var events: [SpikeEvent] = []
        events.reserveCapacity(Self.chunkSize)

        var sender = generator.element(of: SpikeSender.roster)
        var runRemaining = generator.int(in: 1 ... 6)

        for offset in 0 ..< Self.chunkSize {
            if runRemaining == 0 {
                var replacement = generator.element(of: SpikeSender.roster)
                if replacement == sender {
                    let position = SpikeSender.roster.firstIndex(of: sender) ?? 0
                    replacement = SpikeSender.roster[(position + 1) % SpikeSender.roster.count]
                }
                sender = replacement
                runRemaining = generator.int(in: 1 ... 6)
            }
            runRemaining -= 1

            let index = start + offset
            let content = makeContent(using: &generator)
            let reactions = makeReactions(using: &generator)
            events.append(
                SpikeEvent(
                    id: EventID(index),
                    sender: sender,
                    timestamp: timestamp(at: index),
                    content: content,
                    reactions: reactions
                )
            )
        }
        return events
    }

    private func makeContent(using generator: inout SplitMix64) -> EventContent {
        let roll = generator.unitDouble()
        if roll < 0.52 {
            // One-line text: the common case, and the cheapest row to lay out.
            return .text(makeTextBody(lineCount: 1, using: &generator))
        }
        if roll < 0.90 {
            // Multi-paragraph text, skewed short with a long tail up to 40 lines.
            let skew = generator.unitDouble()
            let lines = 2 + Int(pow(skew, 2.2) * Double(Self.maximumLineCount - 2))
            return .text(makeTextBody(lineCount: lines, using: &generator))
        }
        // Image placeholder with a wide spread of aspect ratios: tall portraits stress
        // height estimation far harder than landscape screenshots do.
        let aspectRatio = generator.double(in: 0.45 ..< 2.4)
        let intrinsicWidth = Double(generator.int(in: 220 ... 900))
        let caption: String? = generator.chance(0.35)
            ? generator.element(of: SpikeCorpus.captions)
            : nil
        return .image(
            ImagePlaceholder(
                aspectRatio: aspectRatio,
                intrinsicWidth: intrinsicWidth,
                hue: generator.unitDouble(),
                caption: caption
            )
        )
    }

    private func makeReactions(using generator: inout SplitMix64) -> [Reaction] {
        guard generator.chance(0.18) else { return [] }
        let distinct = generator.int(in: 1 ... 3)
        var reactions: [Reaction] = []
        for _ in 0 ..< distinct {
            let key = generator.element(of: SpikeCorpus.reactionKeys)
            if let existing = reactions.firstIndex(where: { $0.key == key }) {
                reactions[existing].count += 1
            } else {
                reactions.append(Reaction(key: key, count: generator.int(in: 1 ... 9)))
            }
        }
        return reactions
    }

    // MARK: - Arithmetic

    /// Floor division. Swift's `/` truncates toward zero, which would break monotonicity
    /// and chunk alignment across index zero.
    static func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        precondition(divisor > 0, "divisor must be positive")
        let quotient = value / divisor
        return (value % divisor < 0) ? quotient - 1 : quotient
    }
}
