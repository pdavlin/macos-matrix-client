import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-212: the Send Later sheet, the Scheduled strip above the
/// composer, its list, and the clock on a chat-list row. A fixed now
/// (Wednesday 2026-11-18 10:00 in Chicago), calendar, and locale. Local
/// gate only, as the other snapshots (contract R-8).
@MainActor
@Suite(.referenceScaleScreen)
struct SendLaterSnapshotTests {
    private static let now = Date(timeIntervalSince1970: 1_795_017_600)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private static let locale = Locale(identifier: "en_US")

    private static let items = [
        ScheduledMessageItem(
            message: ScheduledMessage(delayId: "a", roomId: "!a", sendAt: now.addingTimeInterval(2 * 3600)),
            text: "Lunch at noon? The usual place on Fifth."
        ),
        ScheduledMessageItem(
            message: ScheduledMessage(delayId: "b", roomId: "!a", sendAt: now.addingTimeInterval(23 * 3600)),
            text: nil
        ),
    ]

    private static let actions = ScheduledMessageActions(sendNow: { _ in }, edit: { _ in }, cancel: { _ in })

    private func host(_ view: some View, background: NSColor = .windowBackgroundColor) -> NSViewController {
        let controller = NSHostingController(rootView: AnyView(view.background(Color(background))))
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    /// A message with a mention and bold text: the plain-text body and the
    /// note, then the time choices.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func sheetWithPlainTextNote() {
        let text = ScheduledMessageText(
            draftText: "[Alice](https://matrix.to/#/@alice:example.org) lunch at **noon**?"
        )
        let sheet = SendLaterSheet(
            chatName: "Design Team",
            text: text,
            now: Self.now,
            calendar: Self.calendar,
            locale: Self.locale,
            schedule: { _ in }
        )
        assertTextFieldSnapshot(of: host(sheet), as: .scaledImage)
    }

    /// "2 scheduled" and the next time, above the composer.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func strip() {
        let strip = ScheduledMessagesStrip(
            items: Self.items,
            busyIds: [],
            isEditable: true,
            now: Self.now,
            calendar: Self.calendar,
            locale: Self.locale,
            actions: Self.actions
        )
        .frame(width: 420)
        .padding()
        assertSnapshot(of: host(strip, background: .controlBackgroundColor), as: .scaledImage)
    }

    /// The list: a message with its text, and one from another device,
    /// which shows "Scheduled message" and cannot be edited. The second is
    /// busy.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func list() {
        let list = ScheduledMessagesList(
            items: Self.items,
            busyIds: ["b"],
            isEditable: true,
            now: Self.now,
            calendar: Self.calendar,
            locale: Self.locale,
            actions: Self.actions
        )
        assertSnapshot(of: host(list), as: .scaledImage)
    }

    /// A chat with a scheduled message has a clock after its title.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func chatRowClock() {
        var model = ChatListRowModel(
            id: "!scheduled",
            title: "Alice",
            isDirect: true,
            preview: "See you at the station at six",
            timestamp: "3:42 PM"
        )
        model.hasScheduledMessages = true
        let row = ChatListRow(model: model, imageLoader: nil).frame(width: 320)
        assertSnapshot(of: host(row, background: .controlBackgroundColor), as: .scaledImage)
    }
}
