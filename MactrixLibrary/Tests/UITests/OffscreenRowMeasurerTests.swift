import SwiftUI
import Testing
@testable import UI

#if os(macOS)
    import AppKit
#endif

/// MATRIX-220: the timeline measures rows offscreen, and a measured row must
/// run none of its actions.
@MainActor
@Suite("Offscreen row measurer", .serialized)
struct OffscreenRowMeasurerTests {
    private static let proposal = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)

    init() {
        #if os(macOS)
            _ = NSApplication.shared
        #endif
    }

    @Test("Rows of one type run no onChange, onAppear, or task while measured")
    func sameTypeRowsRunNoActions() async throws {
        let log = ActionLog()
        let measurer = OffscreenRowMeasurer()

        for index in 0 ..< 8 {
            _ = measurer.size(of: ProbeRow(key: "row \(index)", log: log), in: Self.proposal)
        }
        try await settle()

        #expect(log.changes == 0)
        #expect(log.appears == 0)
        #expect(log.tasks == 0)
    }

    @Test("Rows with their own identity run no onChange, onAppear, or task while measured")
    func identifiedRowsRunNoActions() async throws {
        let log = ActionLog()
        let measurer = OffscreenRowMeasurer()

        for index in 0 ..< 8 {
            _ = measurer.size(of: ProbeRow(key: "row \(index)", log: log).id(index), in: Self.proposal)
            // A turn of the main queue between measures, as between two
            // table updates.
            try await settle(milliseconds: 20)
        }
        try await settle()

        #expect(log.changes == 0)
        #expect(log.appears == 0)
        #expect(log.tasks == 0)
    }

    @Test("The size is the size the view takes")
    func sizeIsTheViewSize() {
        let measurer = OffscreenRowMeasurer()

        let short = measurer.size(of: Color.clear.frame(width: 120, height: 24), in: Self.proposal)
        let tall = measurer.size(of: Color.clear.frame(width: 80, height: 96), in: Self.proposal)
        let again = measurer.size(of: Color.clear.frame(width: 120, height: 24), in: Self.proposal)

        #expect(short == CGSize(width: 120, height: 24))
        #expect(tall == CGSize(width: 80, height: 96))
        #expect(again == short)
    }

    /// Suspends the test, so the main queue dispatches what SwiftUI deferred
    /// to the end of the run loop turn.
    private func settle(milliseconds: Int = 200) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

@MainActor
private final class ActionLog {
    var changes = 0
    var appears = 0
    var tasks = 0
}

/// A row with the modifiers that ran in the old measurement host: an
/// `onChange` on the row's value, as the timeline row's Edit menu target
/// has, and a `task(id:)`, as the message body and the avatar have.
private struct ProbeRow: View {
    let key: String
    let log: ActionLog

    var body: some View {
        Text(verbatim: key)
            .onChange(of: key) { _, _ in log.changes += 1 }
            .onAppear { log.appears += 1 }
            .task(id: key) { log.tasks += 1 }
    }
}
