import Foundation
import Observation

/// The state of one target of a broadcast run (MATRIX-168).
public enum BroadcastTargetState: Equatable, Sendable {
    /// Not sent. The state of every target before the run, and of the
    /// targets a stop left out.
    case waiting
    /// The send call is in flight.
    case sending
    /// The room's send queue has the message.
    case sent
    /// The send call threw. The value is a short reason for the user.
    case failed(String)
}

/// The counts of a broadcast run.
public struct BroadcastSummary: Equatable, Sendable {
    public var sent: Int
    public var failed: Int
    /// The targets that are still waiting, or in flight.
    public var notSent: Int

    public init(sent: Int = 0, failed: Int = 0, notSent: Int = 0) {
        self.sent = sent
        self.failed = failed
        self.notSent = notSent
    }

    /// The targets the run is done with: sent or failed.
    public var completed: Int {
        sent + failed
    }

    public var total: Int {
        sent + failed + notSent
    }
}

/// One broadcast: the same text to each target, one send at a time, in
/// order (MATRIX-168; contract §11, 2026-11-16, decision 2).
///
/// - A failure does not stop the run: the target becomes `.failed` and the
///   run continues.
/// - `stop()` ends the run after the send in flight. That send is not
///   abandoned: its target becomes `.sent` or `.failed`. The targets after
///   it stay `.waiting`. A stop does not recall what was sent.
/// - `retryFailed()` sends again to the failed targets only. A target that
///   is `.sent` never gets a second message.
///
/// The send and the pause are injected, so tests use no network and no
/// clock.
///
/// ```swift
/// let run = BroadcastRun(targets: targets, text: "Lunch at noon",
///                        send: { target, text in try await client.send(text, to: target.roomId) },
///                        pause: { try? await Task.sleep(for: .milliseconds(400)) })
/// await run.start()
/// // run.summary == BroadcastSummary(sent: 3, failed: 0, notSent: 0)
/// ```
@MainActor @Observable
public final class BroadcastRun {
    public typealias Send = @MainActor (_ target: BroadcastTarget, _ text: String) async throws -> Void
    public typealias Pause = @MainActor () async -> Void

    public enum Phase: Equatable, Sendable {
        /// Before `start()`.
        case idle
        /// Sends are in progress.
        case running
        /// `stop()` was called and one send is still in flight.
        case stopping
        /// The run ended: all targets done, or stopped.
        case finished
    }

    /// The longest failure reason the run keeps.
    public static let reasonLimit = 120

    /// The targets, in send order.
    public let targets: [BroadcastTarget]
    /// The text every target gets.
    public let text: String
    public private(set) var phase: Phase = .idle
    /// The state of each target, by target ID.
    public private(set) var states: [String: BroadcastTargetState]

    @ObservationIgnored private let send: Send
    @ObservationIgnored private let pause: Pause
    @ObservationIgnored private var stopRequested = false

    /// - Parameters:
    ///   - targets: the checked targets, in sidebar order. A second target
    ///     with an ID or a room the list already holds is dropped, so no
    ///     room gets the message twice.
    ///   - text: the message.
    ///   - send: sends the text to one target. A throw is a failure.
    ///   - pause: waits between two sends.
    public init(targets: [BroadcastTarget], text: String, send: @escaping Send, pause: @escaping Pause) {
        var seenIds = Set<String>()
        var seenRooms = Set<String>()
        let unique = targets.filter { seenIds.insert($0.id).inserted && seenRooms.insert($0.roomId).inserted }
        self.targets = unique
        self.text = text
        self.send = send
        self.pause = pause
        self.states = Dictionary(uniqueKeysWithValues: unique.map { ($0.id, BroadcastTargetState.waiting) })
    }

    /// The state of a target. A target the run does not hold is waiting.
    public func state(of targetId: String) -> BroadcastTargetState {
        states[targetId] ?? .waiting
    }

    /// Whether sends are in progress or one is still in flight.
    public var isActive: Bool {
        phase == .running || phase == .stopping
    }

    public var summary: BroadcastSummary {
        var summary = BroadcastSummary()
        for target in targets {
            switch state(of: target.id) {
            case .sent: summary.sent += 1
            case .failed: summary.failed += 1
            case .waiting, .sending: summary.notSent += 1
            }
        }
        return summary
    }

    /// Sends to every waiting target, in order. Returns when the run ends.
    /// Does nothing if the run started before.
    public func start() async {
        guard phase == .idle else { return }
        await run(targets.map(\.id))
    }

    /// Ends the run after the send in flight. Does nothing if no run is in
    /// progress.
    public func stop() {
        guard phase == .running else { return }
        stopRequested = true
        phase = .stopping
    }

    /// Sends again to the failed targets, in order. Returns when that run
    /// ends. Does nothing while a run is in progress or with no failure.
    public func retryFailed() async {
        guard phase == .finished else { return }
        let failedIds = targets.map(\.id).filter {
            if case .failed = state(of: $0) {
                return true
            }
            return false
        }
        guard !failedIds.isEmpty else { return }
        for id in failedIds {
            states[id] = .waiting
        }
        await run(failedIds)
    }

    private func run(_ ids: [String]) async {
        let wanted = Set(ids)
        phase = .running
        stopRequested = false
        var isFirst = true
        for target in targets where wanted.contains(target.id) {
            if stopRequested { break }
            // Only a waiting target gets a send, so nothing is sent twice.
            guard state(of: target.id) == .waiting else { continue }
            if !isFirst {
                await pause()
                if stopRequested { break }
            }
            isFirst = false
            states[target.id] = .sending
            do {
                try await send(target, text)
                states[target.id] = .sent
            } catch {
                states[target.id] = .failed(Self.reason(for: error))
            }
        }
        phase = .finished
    }

    /// A short reason for a failed send: the error's own description, on
    /// one line, cut to `reasonLimit` characters.
    public static func reason(for error: any Error) -> String {
        let description = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let oneLine = description
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !oneLine.isEmpty else { return "The message was not sent." }
        guard oneLine.count > reasonLimit else { return oneLine }
        return String(oneLine.prefix(reasonLimit - 1)) + "…"
    }
}
