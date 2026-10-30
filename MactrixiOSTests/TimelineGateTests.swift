@testable import MactrixiOS
import UIKit
import XCTest

/// MATRIX-87: the iOS timeline regression gate, simulator pass.
///
/// Runs the gate scenarios against the production container on the spike's
/// 10k-event workload and asserts the deterministic bars: anchor positions
/// and re-measure counts. Frame numbers need a device and an optimized build,
/// so they run in app mode (`-TimelineGate`). See spike/GATE.md, "iOS".
@MainActor
final class TimelineGateTests: XCTestCase {
    func testTimelineGateSimulatorPass() async throws {
        #if targetEnvironment(simulator)
            let isSimulator = true
        #else
            let isSimulator = false
        #endif
        try XCTSkipUnless(isSimulator, "The device pass runs in app mode, optimized: spike/GATE.md, iOS.")
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "the test host has no window scene"
        )
        let window = UIWindow(windowScene: scene)
        let host = TimelineGateHostViewController(runsOnAppear: false)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let outcome = await host.runner.run()

        for report in outcome.reports {
            let attachment = try XCTAttachment(
                data: TimelineGateArchive.encoded(report),
                uniformTypeIdentifier: "public.json"
            )
            attachment.name = "timeline-\(report.rendererID)-\(report.scenario)-\(report.environment.kind).json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        TimelineGateArchive.write(outcome)

        XCTAssertNil(outcome.refusal)
        XCTAssertEqual(
            outcome.reports.map(\.scenario),
            ["cold-load", "s1", "s2-quiesced", "s4", "width-change"]
        )
        for verdict in outcome.verdicts {
            XCTAssertTrue(verdict.passed, verdict.summaryLine)
        }
    }
}
