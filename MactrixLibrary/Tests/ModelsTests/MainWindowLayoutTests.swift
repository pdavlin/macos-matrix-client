import Foundation
import Models
import Testing

/// MATRIX-266: the widest a window's content gets.
struct MainWindowLayoutTests {
    @Test func oneScreenGivesItsWidth() {
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(MainWindowLayout.maximumContentWidth(screenFrames: [laptop]) == 1512)
    }

    @Test func screensSideBySideGiveTheirWidthTogether() {
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let display = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        #expect(MainWindowLayout.maximumContentWidth(screenFrames: [laptop, display, left]) == Double(1920 + 1512 + 2560))
    }

    @Test func stackedScreensGiveTheWidestScreen() {
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let above = CGRect(x: -500, y: 982, width: 2560, height: 1440)
        #expect(MainWindowLayout.maximumContentWidth(screenFrames: [laptop, above]) == 2560)
    }

    @Test func noUsableScreenGivesNoLimit() {
        #expect(MainWindowLayout.maximumContentWidth(screenFrames: []) == nil)
        #expect(MainWindowLayout.maximumContentWidth(screenFrames: [.zero, .null]) == nil)
    }

    @Test func aColumnMaximumLeavesRoomForTheDefaultColumns() {
        // The sidebar starts at 388 pt and the thread panel at 400 pt.
        #expect(MainWindowLayout.maximumColumnWidth >= 400)
    }
}
