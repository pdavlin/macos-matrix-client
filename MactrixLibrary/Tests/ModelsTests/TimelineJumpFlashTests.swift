import Foundation
import Models
import Testing

/// MATRIX-136: which row shows the jump-to-message flash.
struct TimelineJumpFlashTests {
    private let duration: TimeInterval = 1.5

    @Test func startsIdle() {
        let flash = TimelineJumpFlash(duration: duration)
        #expect(flash.requestedRowId == nil)
        #expect(flash.current == nil)
        #expect(flash.elapsed(forRowId: "a", at: 0) == nil)
    }

    @Test func landingOnTheRequestedRowStartsTheFlash() {
        var flash = TimelineJumpFlash(duration: duration)
        flash.request(rowId: "a")
        let landed = flash.land(rowId: "a", at: 10)
        #expect(landed)
        #expect(flash.requestedRowId == nil)
        #expect(flash.current == TimelineJumpFlash.Flash(rowId: "a", startTime: 10))
        #expect(flash.elapsed(forRowId: "a", at: 10.5) == 0.5)
    }

    @Test func aRequestWithoutALandingDoesNotFlash() {
        var flash = TimelineJumpFlash(duration: duration)
        flash.request(rowId: "a")
        #expect(flash.elapsed(forRowId: "a", at: 0) == nil)
    }

    @Test func aLandingWithoutARequestDoesNotFlash() {
        var flash = TimelineJumpFlash(duration: duration)
        let landed = flash.land(rowId: "a", at: 0)
        #expect(!landed)
        #expect(flash.current == nil)
    }

    @Test func aNewerRequestReplacesTheOlderOne() {
        var flash = TimelineJumpFlash(duration: duration)
        flash.request(rowId: "a")
        flash.request(rowId: "b")
        // The scroll toward "a" ends late: it must not flash.
        let landedOnA = flash.land(rowId: "a", at: 1)
        #expect(!landedOnA)
        #expect(flash.current == nil)
        let landedOnB = flash.land(rowId: "b", at: 2)
        #expect(landedOnB)
        #expect(flash.current?.rowId == "b")
    }

    @Test func aLandingFlashesOnlyOnce() {
        var flash = TimelineJumpFlash(duration: duration)
        flash.request(rowId: "a")
        let firstLanding = flash.land(rowId: "a", at: 0)
        #expect(firstLanding)
        let secondLanding = flash.land(rowId: "a", at: 1)
        #expect(!secondLanding)
        #expect(flash.current?.startTime == 0)
    }

    @Test func otherRowsShowNoFlash() {
        var flash = TimelineJumpFlash(duration: duration)
        flash.request(rowId: "a")
        flash.land(rowId: "a", at: 0)
        // A recycled row view bound to another row must clear.
        #expect(flash.elapsed(forRowId: "b", at: 0.2) == nil)
    }

    @Test func theFlashEndsAfterItsDuration() {
        var flash = TimelineJumpFlash(duration: duration)
        flash.request(rowId: "a")
        flash.land(rowId: "a", at: 0)
        #expect(flash.elapsed(forRowId: "a", at: 1.49) != nil)
        #expect(flash.elapsed(forRowId: "a", at: 1.5) == nil)
        #expect(flash.elapsed(forRowId: "a", at: 30) == nil)
    }

    @Test func aClockBeforeTheStartShowsNoFlash() {
        var flash = TimelineJumpFlash(duration: duration)
        flash.request(rowId: "a")
        flash.land(rowId: "a", at: 5)
        #expect(flash.elapsed(forRowId: "a", at: 4) == nil)
    }

    @Test func aSecondJumpMovesTheFlash() {
        var flash = TimelineJumpFlash(duration: duration)
        flash.request(rowId: "a")
        flash.land(rowId: "a", at: 0)
        flash.request(rowId: "b")
        // The first flash keeps going until the second scroll lands.
        #expect(flash.elapsed(forRowId: "a", at: 0.3) == 0.3)
        flash.land(rowId: "b", at: 0.4)
        #expect(flash.elapsed(forRowId: "a", at: 0.5) == nil)
        #expect(flash.elapsed(forRowId: "b", at: 0.5) != nil)
    }

    // MARK: - Keyframes

    @Test func keyframesRiseToThePeakAndFall() {
        let keyframes = TimelineJumpFlash.keyframes(peakOpacity: 0.25, peakFraction: 0.2, reduceMotion: false)
        #expect(keyframes.values == [0, 0.25, 0])
        #expect(keyframes.keyTimes == [0, 0.2, 1])
    }

    @Test func reduceMotionStartsAtThePeakAndOnlyFades() {
        let keyframes = TimelineJumpFlash.keyframes(peakOpacity: 0.25, peakFraction: 0.2, reduceMotion: true)
        #expect(keyframes.values == [0.25, 0])
        #expect(keyframes.keyTimes == [0, 1])
    }

    @Test func thePeakTimeStaysInsideTheDuration() {
        let late = TimelineJumpFlash.keyframes(peakOpacity: 0.25, peakFraction: 3, reduceMotion: false)
        #expect(late.keyTimes == [0, 1, 1])
        let early = TimelineJumpFlash.keyframes(peakOpacity: 0.25, peakFraction: -1, reduceMotion: false)
        #expect(early.keyTimes == [0, 0, 1])
    }
}
