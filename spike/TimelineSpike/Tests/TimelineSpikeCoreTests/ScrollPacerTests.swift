import CoreGraphics
import Foundation
import Testing
@testable import TimelineSpikeCore

@Suite("Scroll pacer")
struct ScrollPacerTests {
    /// The reading speed every automated scenario drives at, from `ScrollDriver`.
    static let readingSpeed: CGFloat = 250

    private static let pacer = ScrollPacer(pointsPerSecond: readingSpeed)

    @Test("Travel is the reading speed times elapsed time")
    func travelIsLinear() {
        #expect(Self.pacer.travel(elapsed: 1) == 250)
        #expect(Self.pacer.travel(elapsed: 0.5) == 125)
        #expect(Self.pacer.travel(elapsed: 30) == 7500)
    }

    /// The property the whole re-pacing rests on: a scenario of a given duration covers the
    /// same distance whatever the callback stream did, because the offset is a function of
    /// time and not of a step count.
    @Test("Total travel depends on duration, not on how many callbacks arrived")
    func travelIsIndependentOfCallbackCount() {
        let duration: TimeInterval = 30
        // A clean 120Hz stream, and one that lost two callbacks in every three.
        let dense = Self.travelled(overCallbacks: 3600, duration: duration)
        let sparse = Self.travelled(overCallbacks: 1200, duration: duration)
        #expect(abs(dense - sparse) < 0.001)
        #expect(abs(dense - Self.readingSpeed * CGFloat(duration)) < 0.001)
    }

    /// Distance a stream of evenly spaced callbacks covers, summed the way the driver
    /// applies it: each callback moves the viewport to where its own timestamp says.
    private static func travelled(overCallbacks count: Int, duration: TimeInterval) -> CGFloat {
        var distance: CGFloat = 0
        var previous: CGFloat = 0
        for callback in 1 ... count {
            let elapsed = duration * TimeInterval(callback) / TimeInterval(count)
            let current = pacer.travel(elapsed: elapsed)
            distance += current - previous
            previous = current
        }
        return distance
    }

    @Test("Elapsed times at or below zero do not move the viewport")
    func travelClampsAtTheStart() {
        #expect(Self.pacer.travel(elapsed: 0) == 0)
        #expect(Self.pacer.travel(elapsed: -1) == 0)
    }

    @Test("Travel is monotonic across a callback stream")
    func travelNeverGoesBackwards() {
        var previous: CGFloat = -1
        for tick in 0 ... 1200 {
            let travel = Self.pacer.travel(elapsed: TimeInterval(tick) / 120)
            #expect(travel >= previous)
            previous = travel
        }
    }

    // MARK: - Folding

    @Test("The fold turns a sweep into a triangle over the band")
    func foldReversesAtBothEnds() {
        let band: CGFloat = 500
        // 250pt/s over a 500pt band: 2s out, 2s back, a 4s period.
        #expect(Self.pacer.foldedTravel(elapsed: 0, band: band) == 0)
        #expect(Self.pacer.foldedTravel(elapsed: 1, band: band) == 250)
        #expect(Self.pacer.foldedTravel(elapsed: 2, band: band) == 500)
        #expect(Self.pacer.foldedTravel(elapsed: 3, band: band) == 250)
        #expect(abs(Self.pacer.foldedTravel(elapsed: 4, band: band)) < 0.000001)
        #expect(Self.pacer.foldedTravel(elapsed: 5, band: band) == 250)
    }

    @Test("The fold never leaves the band")
    func foldStaysInsideTheBand() {
        let band: CGFloat = 906 * 4
        for tick in 0 ... 3600 {
            let folded = Self.pacer.foldedTravel(elapsed: TimeInterval(tick) / 120, band: band)
            #expect(folded >= 0)
            #expect(folded <= band)
        }
    }

    /// The fold changes direction, not speed. Summed without sign, a folded run covers
    /// exactly the distance an unfolded one does, which is what keeps S3's scroll workload
    /// equal to S1's.
    @Test("The fold preserves the reading speed")
    func foldPreservesSpeed() {
        let band: CGFloat = 1000
        let quantum: TimeInterval = 1.0 / 120
        let tickCount = 2000
        var distance: CGFloat = 0
        for tick in 0 ..< tickCount {
            let current = Self.pacer.foldedTravel(elapsed: TimeInterval(tick) * quantum, band: band)
            let next = Self.pacer.foldedTravel(elapsed: TimeInterval(tick + 1) * quantum, band: band)
            distance += abs(next - current)
        }
        let unfolded = Self.pacer.travel(elapsed: TimeInterval(tickCount) * quantum)
        #expect(abs(distance - unfolded) < 0.001)
    }

    @Test("A band of zero or less folds to no travel")
    func foldRefusesAnEmptyBand() {
        #expect(Self.pacer.foldedTravel(elapsed: 5, band: 0) == 0)
        #expect(Self.pacer.foldedTravel(elapsed: 5, band: -100) == 0)
    }
}
