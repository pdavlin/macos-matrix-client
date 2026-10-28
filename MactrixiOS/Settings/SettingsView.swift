import Core
import OSLog
import SwiftUI

/// The account facts the settings screen shows, read from Core's session.
struct SettingsAccount: Equatable {
    let userID: String
    let deviceID: String
    let homeserver: String

    init(userID: String, deviceID: String, homeserver: String) {
        self.userID = userID
        self.deviceID = deviceID
        self.homeserver = homeserver
    }

    init(session: UserSession) {
        self.init(userID: session.userID, deviceID: session.deviceID, homeserver: session.homeserverURL)
    }
}

/// The minimal iOS settings: account, sign out, and a placeholder for push
/// notifications (MATRIX-89).
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var confirmsSignOut = false
    @State private var isSigningOut = false
    @State private var signOutError: String?

    private var account: SettingsAccount? {
        (try? appState.matrixClient?.userSession()).map(SettingsAccount.init(session:))
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                notificationsSection
                signOutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if let account {
                LabeledContent("User", value: account.userID)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settingsUserID")
                LabeledContent("Device", value: account.deviceID)
                    .textSelection(.enabled)
                LabeledContent("Homeserver", value: account.homeserver)
            } else {
                Text("Not signed in")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notificationsSection: some View {
        Section {
            Label("Push notifications are not available yet.", systemImage: "bell.badge")
                .foregroundStyle(.secondary)
        } header: {
            Text("Notifications")
        } footer: {
            Text("The app shows new messages only while it is open.")
        }
    }

    private var signOutSection: some View {
        Section {
            Button("Sign Out", role: .destructive) {
                confirmsSignOut = true
            }
            .disabled(isSigningOut || account == nil)
            .accessibilityIdentifier("signOutButton")
            .confirmationDialog("Sign out of this device?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await signOut() }
                }
            } message: {
                Text("This removes the session and its local encryption keys from this device.")
            }
        } footer: {
            if let signOutError {
                Text(signOutError)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Sign out goes through Core: `AppState.reset()` stops sync, logs out,
    /// and removes the session store and keychain items. The root view leaves
    /// the signed-in shell when `matrixClient` becomes nil.
    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await appState.reset()
        } catch {
            Logger.settings.error("sign out failed: \(error)")
            signOutError = error.localizedDescription
        }
    }
}
