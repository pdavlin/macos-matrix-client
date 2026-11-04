import Core
import SwiftUI

@main
struct MactrixiOSApp: App {
    @State private var model = RootViewModel(appState: AppState())

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .environment(model.appState)
    }
}
