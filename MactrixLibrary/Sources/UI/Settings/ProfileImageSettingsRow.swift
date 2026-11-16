import Models
import SwiftUI

/// What the profile image control shows besides the image (MATRIX-163).
public enum ProfileImageChangeState: Equatable, Sendable {
    case idle
    /// An upload or a removal runs.
    case working
    /// The last change failed, with the message to show.
    case failed(String)
}

/// Settings > Account: the account's profile image, with the controls to set
/// and remove it (MATRIX-163).
///
/// The view draws state and reports clicks. The owner picks the file, calls
/// the SDK, and holds the state. The view lives in the UI library so its
/// snapshot test exercises the shipped view.
public struct ProfileImageSettingsRow: View {
    let profile: OwnProfile
    let state: ProfileImageChangeState
    let imageLoader: ImageLoader?
    let choose: () -> Void
    let remove: () -> Void

    public static let avatarSize: CGFloat = 48

    public init(
        profile: OwnProfile,
        state: ProfileImageChangeState,
        imageLoader: ImageLoader?,
        choose: @escaping () -> Void,
        remove: @escaping () -> Void
    ) {
        self.profile = profile
        self.state = state
        self.imageLoader = imageLoader
        self.choose = choose
        self.remove = remove
    }

    private var hasImage: Bool {
        !(profile.avatarUrl ?? "").isEmpty
    }

    public var body: some View {
        LabeledContent("Profile image") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    AvatarImage(userProfile: profile, imageLoader: imageLoader)
                        .frame(width: Self.avatarSize, height: Self.avatarSize)
                        .clipShape(Circle())
                        .accessibilityLabel(hasImage ? "Profile image" : "No profile image")

                    Button("Choose Image…", action: choose)
                    Button("Remove", role: .destructive, action: remove)
                        .disabled(!hasImage)

                    if state == .working {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .disabled(state == .working)

                if case let .failed(message) = state {
                    Text(message)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
