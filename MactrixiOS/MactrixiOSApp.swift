import Core
import SwiftUI

@main
struct MactrixiOSApp: App {
    /// APNs registration callbacks (MATRIX-89).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = RootViewModel(appState: AppState())

    init() {
        SessionStorageLocation.resolve()
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .environment(model.appState)
    }
}
