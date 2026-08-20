import Foundation

public struct PaginationDriverConfiguration: Sendable, Equatable, Codable {
    /// Events prepended per batch. The contract's back-pagination unit is 50.
    public var batchSize: Int
    /// Distance from the top of the content, in points, that arms an automatic prepend.
    public var triggerDistance: Double
    /// Minimum wall-clock gap between automatic prepends. Without it a renderer that keeps
    /// the viewport pinned near the top would prepend on every frame.
    public var minimumInterval: TimeInterval
    /// When false only the manual trigger prepends, which is what the scripted scenarios
    /// in SCENARIOS.md use.
    public var isAutomatic: Bool

    public init(
        batchSize: Int = 50,
        triggerDistance: Double = 600,
        minimumInterval: TimeInterval = 0.35,
        isAutomatic: Bool = true
    ) {
        self.batchSize = batchSize
        self.triggerDistance = triggerDistance
        self.minimumInterval = minimumInterval
        self.isAutomatic = isAutomatic
    }

    public static let `default` = PaginationDriverConfiguration()
}

/// Prepends older events, either automatically as the viewport nears the top of the loaded
/// content or on an explicit manual trigger.
///
/// The manual trigger exists because automatic prepends are not reproducible: they depend
/// on how fast the human scrolled. Every scripted scenario uses `prependNow(store:)` so the
/// two candidates absorb the same number of prepends at comparable scroll offsets.
@MainActor
public final class PaginationDriver {
    public var configuration: PaginationDriverConfiguration
    public private(set) var automaticPrependCount = 0
    public private(set) var manualPrependCount = 0
    public private(set) var lastPrependedAt: Date?

    /// Called immediately before the store changes, so the harness can snapshot the anchor.
    public var willPrepend: (() -> Void)?
    /// Called immediately after the store changes.
    public var didPrepend: ((Range<Int>) -> Void)?

    /// Injectable so tests can advance time without sleeping. Main-actor isolated along
    /// with the rest of the driver, so it does not need to be `Sendable`.
    private var clock: () -> Date

    public init(
        configuration: PaginationDriverConfiguration = .default,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.clock = clock
    }

    public func reset() {
        automaticPrependCount = 0
        manualPrependCount = 0
        lastPrependedAt = nil
    }

    /// Prepends one batch unconditionally.
    @discardableResult
    public func prependNow(store: TimelineStore) -> Range<Int> {
        manualPrependCount += 1
        return performPrepend(store: store)
    }

    /// Reports the viewport's distance from the top of the loaded content. Prepends when
    /// the distance is inside the trigger band and the cooldown has expired.
    @discardableResult
    public func viewportDidScroll(distanceFromTop: Double, store: TimelineStore) -> Range<Int>? {
        guard configuration.isAutomatic else { return nil }
        guard distanceFromTop <= configuration.triggerDistance else { return nil }
        let now = clock()
        if let last = lastPrependedAt, now.timeIntervalSince(last) < configuration.minimumInterval {
            return nil
        }
        automaticPrependCount += 1
        return performPrepend(store: store)
    }

    private func performPrepend(store: TimelineStore) -> Range<Int> {
        willPrepend?()
        let inserted = store.prepend(count: configuration.batchSize)
        lastPrependedAt = clock()
        didPrepend?(inserted)
        return inserted
    }
}
