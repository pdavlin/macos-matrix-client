import CoreGraphics
import Testing
import Tokens
@testable import UI

struct MediaRowLayoutTests {
    // MARK: - aspectRatio

    @Test func aspectRatioFromBothDimensions() throws {
        let ratio = try #require(MediaRowLayout.aspectRatio(width: 1600, height: 900))

        #expect(abs(ratio - CGFloat(1600) / CGFloat(900)) < 0.0001)
    }

    @Test func aspectRatioIsNilWithoutBothDimensions() {
        #expect(MediaRowLayout.aspectRatio(width: nil, height: 900) == nil)
        #expect(MediaRowLayout.aspectRatio(width: 1600, height: nil) == nil)
        #expect(MediaRowLayout.aspectRatio(width: nil, height: nil) == nil)
    }

    @Test func aspectRatioIsNilForZeroDimensions() {
        #expect(MediaRowLayout.aspectRatio(width: 0, height: 900) == nil)
        #expect(MediaRowLayout.aspectRatio(width: 1600, height: 0) == nil)
    }

    // MARK: - maxHeight

    @Test func shortMediaKeepsItsOwnHeight() {
        #expect(MediaRowLayout.maxHeight(height: 120) == 120)
    }

    @Test func tallMediaIsCappedAtTheToken() {
        #expect(MediaRowLayout.maxHeight(height: 4000) == BubbleToken.mediaMaxHeight)
    }

    @Test func unknownHeightFallsBackToTheToken() {
        #expect(MediaRowLayout.maxHeight(height: nil) == BubbleToken.mediaMaxHeight)
        #expect(MediaRowLayout.maxHeight(height: 0) == BubbleToken.mediaMaxHeight)
    }
}
