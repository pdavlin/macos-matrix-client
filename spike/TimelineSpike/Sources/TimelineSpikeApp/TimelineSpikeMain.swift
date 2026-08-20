import AppKit
import SwiftUI
import TimelineSpikeCore

/// An SPM executable is not a bundled `.app`, so AppKit starts it as a background process
/// with no Dock tile and no key window. The delegate promotes it to a regular app.
final class SpikeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Line-buffer stdout so the report path appears immediately even when the app is
        // launched with its output piped rather than attached to a terminal.
        setvbuf(stdout, nil, _IOLBF, 0)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        print("[TimelineSpike] working directory: \(FileManager.default.currentDirectoryPath)")
        print("[TimelineSpike] reports are written here by \"Dump stats\".")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct TimelineSpikeMain: App {
    @NSApplicationDelegateAdaptor(SpikeAppDelegate.self) private var delegate
    @State private var harness = SpikeHarness()

    var body: some Scene {
        Window("Timeline Spike", id: "timeline-spike") {
            HarnessRootView(harness: harness)
        }
        .defaultSize(width: 1080, height: 860)
        .commands {
            CommandMenu("Spike") {
                Button("Prepend 50 Now") { harness.prependNow() }
                    .keyboardShortcut("p", modifiers: [.command])
                Button(harness.isMutating ? "Stop Mutation Storm" : "Start Mutation Storm") {
                    harness.toggleMutating()
                }
                .keyboardShortcut("m", modifiers: [.command])
                Button("Mutate Once") { harness.mutateOnce() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Reset Instruments") { harness.resetInstrumentation() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Dump Stats to JSON") { harness.dumpReport() }
                    .keyboardShortcut("d", modifiers: [.command])
            }
        }
    }
}
