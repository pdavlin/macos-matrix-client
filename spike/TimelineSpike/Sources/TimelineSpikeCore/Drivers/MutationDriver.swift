import Foundation

public struct MutationDriverConfiguration: Sendable, Equatable, Codable {
    /// Mutations emitted per tick. Values below two disable the on/off-screen guarantee.
    public var mutationsPerTick: Int
    /// Tick rate in hertz.
    public var ticksPerSecond: Double
    /// Probability that a discretionary mutation targets the visible range. Slots 0 and 1
    /// are not discretionary: see `step(store:visibleRange:)`.
    public var onScreenBias: Double
    /// Probability that a text target receives a body edit rather than a reaction change.
    public var editShare: Double

    public init(
        mutationsPerTick: Int = 6,
        ticksPerSecond: Double = 10,
        onScreenBias: Double = 0.5,
        editShare: Double = 0.45
    ) {
        self.mutationsPerTick = mutationsPerTick
        self.ticksPerSecond = ticksPerSecond
        self.onScreenBias = onScreenBias
        self.editShare = editShare
    }

    public static let `default` = MutationDriverConfiguration()
}

/// Applies random edits and reaction changes to events that are already laid out.
///
/// ## The on/off-screen guarantee
///
/// A mutation storm that only touches visible rows tests invalidation. A storm that only
/// touches off-screen rows tests height bookkeeping and anchor stability. Both matter, and
/// a purely random target distribution makes the mix depend on the viewport size.
///
/// So each tick is structured: slot 0 always targets a visible item, slot 1 always targets
/// an off-screen item, and every later slot follows `onScreenBias`. With
/// `mutationsPerTick >= 2` and a viewport that covers part of the window, every tick
/// exercises both paths. Unit tests assert exactly that.
@MainActor
public final class MutationDriver {
    public var configuration: MutationDriverConfiguration
    public private(set) var appliedCount = 0
    public private(set) var lastBatch: [Mutation] = []

    private var generator: SplitMix64
    private let eventGenerator: SyntheticEventGenerator
    private let seed: UInt64

    public init(seed: UInt64, configuration: MutationDriverConfiguration = .default) {
        self.seed = seed
        self.configuration = configuration
        self.generator = SplitMix64(seed: SplitMix64.derivedSeed(from: seed, salt: 0x4D_5554))
        self.eventGenerator = SyntheticEventGenerator(seed: seed)
    }

    /// Restarts the mutation stream from the seed. Counters reset too.
    public func reset() {
        generator = SplitMix64(seed: SplitMix64.derivedSeed(from: seed, salt: 0x4D_5554))
        appliedCount = 0
        lastBatch = []
    }

    /// Emits and applies one tick of mutations.
    ///
    /// - Parameter visibleRange: item indices currently on screen, or `nil` when the
    ///   renderer has not reported a viewport yet. Out-of-bounds ranges are clamped.
    /// - Returns: the mutations that were actually applied, in order.
    @discardableResult
    public func step(store: TimelineStore, visibleRange: Range<Int>?) -> [Mutation] {
        let total = store.items.count
        guard total > 0, configuration.mutationsPerTick > 0 else {
            lastBatch = []
            return []
        }

        let visible = visibleRange.flatMap { clamped($0, to: total) }
        let hasVisible = (visible?.isEmpty == false)
        let hasOffScreen = visible.map { $0.count < total } ?? true

        var applied: [Mutation] = []
        applied.reserveCapacity(configuration.mutationsPerTick)

        for slot in 0 ..< configuration.mutationsPerTick {
            let target = pickTarget(slot: slot, total: total, visible: visible,
                                    hasVisible: hasVisible, hasOffScreen: hasOffScreen)
            guard let mutation = makeMutation(for: store.items[target].event) else { continue }
            guard store.apply(mutation) != nil else { continue }
            applied.append(mutation)
        }

        appliedCount += applied.count
        lastBatch = applied
        return applied
    }

    // MARK: - Target selection

    private func pickTarget(
        slot: Int,
        total: Int,
        visible: Range<Int>?,
        hasVisible: Bool,
        hasOffScreen: Bool
    ) -> Int {
        if slot == 0, hasVisible, let visible {
            return generator.int(in: visible)
        }
        if slot == 1, hasOffScreen {
            return offScreenIndex(total: total, visible: visible)
        }
        if hasVisible, let visible, generator.chance(configuration.onScreenBias) {
            return generator.int(in: visible)
        }
        if hasOffScreen {
            return offScreenIndex(total: total, visible: visible)
        }
        return generator.int(in: 0 ..< total)
    }

    /// Uniform draw from the complement of the visible range.
    private func offScreenIndex(total: Int, visible: Range<Int>?) -> Int {
        guard let visible, !visible.isEmpty else {
            return generator.int(in: 0 ..< total)
        }
        let complementCount = total - visible.count
        guard complementCount > 0 else {
            return generator.int(in: 0 ..< total)
        }
        let draw = generator.int(in: 0 ..< complementCount)
        return draw < visible.lowerBound ? draw : draw + visible.count
    }

    private func clamped(_ range: Range<Int>, to total: Int) -> Range<Int>? {
        let lower = max(0, min(range.lowerBound, total))
        let upper = max(lower, min(range.upperBound, total))
        return lower < upper ? lower ..< upper : nil
    }

    // MARK: - Mutation construction

    /// Text events may receive an edit or a reaction change. Image placeholders have no
    /// editable body, so they always receive a reaction change.
    private func makeMutation(for event: SpikeEvent) -> Mutation? {
        if let body = event.content.textBody, generator.chance(configuration.editShare) {
            let lineCount = perturbedLineCount(from: body.lineCount)
            let newBody = eventGenerator.makeTextBody(lineCount: lineCount, using: &generator)
            return .editText(event.id, newBody: newBody)
        }
        return reactionMutation(for: event)
    }

    private func reactionMutation(for event: SpikeEvent) -> Mutation? {
        if !event.reactions.isEmpty, generator.chance(0.45) {
            let victim = generator.element(of: event.reactions)
            return .removeReaction(event.id, key: victim.key)
        }
        return .addReaction(event.id, key: generator.element(of: SpikeCorpus.reactionKeys))
    }

    /// Produces a line count that always differs from the current one, so every edit is a
    /// real height change rather than a no-op relayout.
    private func perturbedLineCount(from current: Int) -> Int {
        let maximum = SyntheticEventGenerator.maximumLineCount
        let delta = generator.int(in: 1 ... 11)
        let grows = generator.chance(0.5)
        var candidate = grows ? current + delta : current - delta
        candidate = min(maximum, max(1, candidate))
        if candidate == current {
            candidate = current < maximum ? current + 1 : current - 1
        }
        return candidate
    }
}
