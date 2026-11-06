import Core
import SwiftUI
import Utils

@main
struct MactrixiOSApp: App {
    /// APNs registration callbacks (MATRIX-89).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = RootViewModel(appState: AppState())

    init() {
        // MATRIX-122: raise the open-file soft limit before any store opens.
        FileDescriptorLimit.raiseSoftLimit()
        SessionStorageLocation.resolve()
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model).timelineFixtureOverride().timelineGateOverride()
        }
        .environment(model.appState)
    }
}
