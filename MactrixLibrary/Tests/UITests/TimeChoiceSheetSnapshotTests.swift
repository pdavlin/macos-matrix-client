import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-207: the time sheet of "Custom…" with a typed time, and with
/// text that is not a time. A fixed now (Wednesday 2026-11-18 10:00 in
/// Chicago), calendar, and locale. The typed times use the short-form rule,
/// not NSDataDetector, which reads against the system clock. Local gate
/// only, as the other snapshots (contract R-8).
@MainActor
@Suite(.referenceScaleScreen)
struct TimeChoiceSheetSnapshotTests {
    private static let now = Date(timeIntervalSince1970: 1_795_017_600)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func host(text: String) -> NSViewController {
        let controller = NSHostingController(
            rootView: TimeChoiceSheet(
                title: "Snooze Design Team until",
                confirmLabel: "Snooze",
                now: Self.now,
                calendar: Self.calendar,
                locale: Locale(identifier: "en_US"),
                text: text,
                choose: { _ in }
            )
            .background(Color(NSColor.windowBackgroundColor))
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func typedTime() {
        assertTextFieldSnapshot(of: host(text: "in 2 hours"), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func notATime() {
        assertTextFieldSnapshot(of: host(text: "banana"), as: .scaledImage)
    }
}
