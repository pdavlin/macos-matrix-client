import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI
import UniformTypeIdentifiers
import Utils

struct ChangableField: View {
    let name: String
    let value: String
    let onSave: (_ newValue: String) async -> Void

    @State private var isEditing: Bool = false
    @State private var editValue: String = ""
    @State private var saving: Bool = false

    private func save() async {
        saving = true
        await onSave(editValue)
        isEditing = false
        saving = false
    }

    var body: some View {
        if isEditing {
            HStack {
                TextField(name, text: $editValue)
                    .onSubmit { Task { await save() } }
                    .disabled(saving)
                Button("Save") { Task { await save() } }
                Button("Cancel") { isEditing = false }
            }
        } else {
            LabeledContent(name) {
                Text(value)
                    .textSelection(.enabled)
                Button("Edit") {
                    editValue = value
                    isEditing = true
                }
                .padding(.leading, 10)
            }
        }
    }
}

struct AccountSettingsView: View {
    @Environment(AppState.self) var appState

    @State private var logoutError: String?
    @State private var displayName: String?
    @State private var profileImageState: ProfileImageChangeState = .idle
    @State private var isChoosingProfileImage = false

    /// MATRIX-163: reads the picked file, scales it to the upload limit, and
    /// uploads it through the SDK. The decode and encode run off the main
    /// actor.
    private func uploadProfileImage(from url: URL, with matrixClient: MatrixClient) async {
        profileImageState = .working
        let encoded = await Task.detached(priority: .userInitiated) { () -> EncodedThumbnail? in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            return MediaProbe.imageThumbnail(at: url, maxPixelSize: ProfileImageLimit.maxPixelSize, jpegQuality: 0.85)
        }.value
        guard let encoded else {
            profileImageState = .failed("The file is not an image the app can read.")
            return
        }
        do {
            try await matrixClient.uploadOwnAvatar(mimeType: encoded.mimeType, data: encoded.data)
            profileImageState = .idle
        } catch {
            Logger.viewCycle.error("Failed to upload the profile image: \(error)")
            profileImageState = .failed("The upload failed: \(error.localizedDescription)")
        }
    }

    private func removeProfileImage(with matrixClient: MatrixClient) async {
        profileImageState = .working
        do {
            try await matrixClient.removeOwnAvatar()
            profileImageState = .idle
        } catch {
            Logger.viewCycle.error("Failed to remove the profile image: \(error)")
            profileImageState = .failed("The removal failed: \(error.localizedDescription)")
        }
    }

    var body: some View {
        if let matrixClient = appState.matrixClient {
            Form {
                ProfileImageSettingsRow(
                    profile: OwnProfile(
                        userId: (try? matrixClient.client.userId()) ?? "",
                        displayName: displayName,
                        avatarUrl: matrixClient.ownAvatarUrl
                    ),
                    state: profileImageState,
                    imageLoader: matrixClient,
                    choose: { isChoosingProfileImage = true },
                    remove: { Task { await removeProfileImage(with: matrixClient) } }
                )
                .fileImporter(isPresented: $isChoosingProfileImage, allowedContentTypes: [.image]) { result in
                    switch result {
                    case let .success(url):
                        Task { await uploadProfileImage(from: url, with: matrixClient) }
                    case let .failure(error):
                        profileImageState = .failed("The file did not open: \(error.localizedDescription)")
                    }
                }
                .task { await matrixClient.refreshOwnAvatar() }

                ChangableField(name: "Display name", value: displayName ?? "loading...", onSave: { newDisplayName in
                    do {
                        try await matrixClient.client.setDisplayName(name: newDisplayName)
                        displayName = newDisplayName
                    } catch {
                        Logger.viewCycle.error("Failed to update display name: \(error)")
                    }
                })
                .task {
                    do {
                        displayName = try await matrixClient.client.displayName()
                    } catch {
                        Logger.viewCycle.error("Failed to load display name: \(error)")
                    }
                }

                LabeledContent("User") {
                    Text((try? matrixClient.client.userId()) ?? "error")
                        .textSelection(.enabled)
                }

                LabeledContent("Device") {
                    Text((try? matrixClient.client.deviceId()) ?? "error")
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Sign out", role: .destructive) {
                        Task {
                            do {
                                try await appState.reset()
                            } catch {
                                logoutError = error.localizedDescription
                            }
                        }
                    }
                    if let logoutError = logoutError {
                        Text(logoutError)
                            .textSelection(.enabled)
                            .foregroundStyle(Color.red)
                    }
                }

                Button("Clear cache") {
                    Task {
                        try await appState.matrixClient?.clearCache()
                    }
                }
            }
        } else {
            ContentUnavailableView("User not logged in", systemImage: "person")
        }
    }
}

#Preview {
    AccountSettingsView()
}
