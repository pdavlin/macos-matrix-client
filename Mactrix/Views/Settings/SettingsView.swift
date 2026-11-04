import MatrixRustSDK
import SwiftUI
import UI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Account", systemImage: "person") {
                AccountSettingsView()
            }
            Tab("Appearance", systemImage: "eye") {
                AppearanceSettingsView()
            }
            Tab("Composer", systemImage: "square.and.pencil") {
                ComposerSettingsView()
            }
            Tab("Sessions", systemImage: "desktopcomputer.and.macbook") {
                SessionsSettingsView()
            }
        }
        .scenePadding()
        .frame(maxWidth: 450, minHeight: 200)
    }
}
