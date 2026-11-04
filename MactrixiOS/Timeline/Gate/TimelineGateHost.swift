import SwiftUI
import UIKit
#if DEBUG
    import TimelineSpikeCore
#endif

extension View {
    /// DEBUG builds launched with `-TimelineGate` run the iOS timeline gate
    /// instead of this view (MATRIX-87): the scenarios run, the dumps land in
    /// the app's Documents/TimelineGate, and the app exits 0 (pass), 1 (a
    /// bar failed), or 3 (a device run refused to measure). Release builds
    /// return the view as is. See spike/GATE.md, "iOS".
    @ViewBuilder
    func timelineGateOverride() -> some View {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(TimelineGateHostViewController.launchArgument) {
                TimelineGateScreen()
                    .ignoresSafeArea()
            } else {
                self
            }
        #else
            self
        #endif
    }
}

#if DEBUG
    /// Puts the gate's pinned viewport in a window and, in app mode, runs it
    /// (MATRIX-87). The XCTest builds the same controller and calls the
    /// runner itself, so both paths measure the same thing.
    final class TimelineGateHostViewController: UIViewController {
        static let launchArgument = "-TimelineGate"
        /// Exit status when a device run refuses to measure. The Mac gate's
        /// REFUSED code.
        static let refusalExitCode: Int32 = 3

        let runner = TimelineGateRunner()
        private let runsOnAppear: Bool
        private var didStart = false

        init(runsOnAppear: Bool) {
            self.runsOnAppear = runsOnAppear
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            view.addSubview(runner.container)
        }

        /// The viewport sits inside the safe area, as the app's timeline does.
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            runner.container.frame.origin = CGPoint(x: view.safeAreaInsets.left, y: view.safeAreaInsets.top)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard runsOnAppear, !didStart else { return }
            didStart = true
            Task { await runAppMode() }
        }

        private func runAppMode() async {
            print("[TimelineGate] running: \(runner.configuration.initialEventCount) events, seed \(runner.configuration.seed)")
            let outcome = await runner.run()
            for url in TimelineGateArchive.write(outcome) {
                print("[TimelineGate] wrote \(url.path)")
            }
            for verdict in outcome.verdicts {
                print("[TimelineGate] \(verdict.summaryLine)")
            }
            if let refusal = outcome.refusal {
                print("[TimelineGate] refused to measure: \(refusal)")
                exit(Self.refusalExitCode)
            }
            print("[TimelineGate] \(outcome.passed ? "PASS" : "FAIL")")
            exit(outcome.passed ? 0 : 1)
        }
    }

    private struct TimelineGateScreen: UIViewControllerRepresentable {
        func makeUIViewController(context _: Context) -> TimelineGateHostViewController {
            TimelineGateHostViewController(runsOnAppear: true)
        }

        func updateUIViewController(_: TimelineGateHostViewController, context _: Context) {}
    }

    /// Writes a run's dumps under Documents/TimelineGate, one file per
    /// scenario, named like the Mac dumps with the run kind added.
    enum TimelineGateArchive {
        static var directory: URL {
            URL.documentsDirectory.appending(path: "TimelineGate", directoryHint: .isDirectory)
        }

        static func encoded(_ report: TimelineGateReport) throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(report)
        }

        static func fileName(for report: TimelineGateReport, stamp: String) -> String {
            "timeline-\(report.rendererID)-\(report.scenario)-\(report.environment.kind)-\(stamp).json"
        }

        @discardableResult
        static func write(_ outcome: TimelineGateRunner.Outcome) -> [URL] {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = formatter.string(from: Date())
            var written: [URL] = []
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for report in outcome.reports {
                    let url = directory.appending(path: fileName(for: report, stamp: stamp))
                    try encoded(report).write(to: url, options: .atomic)
                    written.append(url)
                }
            } catch {
                print("[TimelineGate] failed to write a dump: \(error)")
            }
            return written
        }
    }
#endif
