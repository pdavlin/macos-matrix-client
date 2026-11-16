import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-163: the own avatar in a message profile row, and the profile image
/// control of the Account settings. The loader holds one solid-color image
/// per URL in its cache, so the avatars draw without a network. Local gate
/// only, as the other snapshots (contract R-8).
@MainActor
struct OwnAvatarSnapshotTests {
    /// Serves a solid-color square for each known URL, from the cache.
    private struct ColorLoader: ImageLoader {
        let colors: [String: NSColor]

        func cachedImage(matrixUrl: String) -> Image? {
            guard let color = colors[matrixUrl] else { return nil }
            let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
                color.setFill()
                rect.fill()
                return true
            }
            return Image(nsImage: image)
        }

        func loadImage(matrixUrl: String, size _: CGSize?) async throws -> Image? {
            cachedImage(matrixUrl: matrixUrl)
        }
    }

    private static let accountUrl = "mxc://a/account"
    private static let memberUrl = "mxc://a/member"
    private static let loader = ColorLoader(colors: [accountUrl: .systemTeal, memberUrl: .systemOrange])

    private struct ProfileEvent: EventTimelineItem {
        let isOwn: Bool
        var memberAvatarUrl: String?

        let isRemote = true
        let isEditable = false
        let sender = "@patrick:example.org"
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let sendState: LocalSendState? = nil
        let localCreatedAt: UInt64? = nil
        let userReadReceipts: [String: Receipt] = [:]
        let canBeRepliedTo = true

        var senderProfileDetails: ProfileDetails {
            .ready(displayName: "Patrick", displayNameAmbiguous: false, avatarUrl: memberAvatarUrl)
        }

        var userId: String { sender }
        var displayName: String? { "Patrick" }
        var avatarUrl: String? { memberAvatarUrl }
    }

    private func profileRow(_ event: ProfileEvent, accountAvatarUrl: String?) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                MessageEventProfileView(event: event, actions: MockMessageEventActions(), imageLoader: Self.loader)
                    .environment(\.ownAccountAvatarUrl, accountAvatarUrl)
                    .frame(width: 320)
                    .background(Color(NSColor.textBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    /// An own message whose member profile has no avatar draws the account's
    /// image (teal).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func ownMessageDrawsAccountImage() {
        assertSnapshot(of: profileRow(ProfileEvent(isOwn: true), accountAvatarUrl: Self.accountUrl), as: .scaledImage)
    }

    /// The member avatar (orange) wins over the account's image.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func ownMessageKeepsMemberImage() {
        let event = ProfileEvent(isOwn: true, memberAvatarUrl: Self.memberUrl)
        assertSnapshot(of: profileRow(event, accountAvatarUrl: Self.accountUrl), as: .scaledImage)
    }

    /// Another user without an avatar keeps initials.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func otherUserKeepsInitials() {
        assertSnapshot(of: profileRow(ProfileEvent(isOwn: false), accountAvatarUrl: Self.accountUrl), as: .scaledImage)
    }

    /// The avatar has a fixed size: the row is as high with the image as with
    /// initials.
    @Test
    func accountImageKeepsRowHeight() {
        let withImage = profileRow(ProfileEvent(isOwn: true), accountAvatarUrl: Self.accountUrl).view.fittingSize.height
        let withInitials = profileRow(ProfileEvent(isOwn: true), accountAvatarUrl: nil).view.fittingSize.height
        #expect(withImage == withInitials)
    }

    // MARK: - Settings control

    private func settingsRow(avatarUrl: String?, state: ProfileImageChangeState) -> NSHostingController<AnyView> {
        let profile = OwnProfile(userId: "@patrick:example.org", displayName: "Patrick", avatarUrl: avatarUrl)
        let controller = NSHostingController(
            rootView: AnyView(
                Form {
                    ProfileImageSettingsRow(profile: profile, state: state, imageLoader: Self.loader, choose: {}, remove: {})
                }
                .frame(width: 450)
                .padding()
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func settingsWithImage() {
        assertSnapshot(of: settingsRow(avatarUrl: Self.accountUrl, state: .idle), as: .scaledImage)
    }

    /// Without an image: initials, and Remove is disabled.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func settingsWithoutImage() {
        assertSnapshot(of: settingsRow(avatarUrl: nil, state: .idle), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func settingsAfterFailure() {
        assertSnapshot(of: settingsRow(avatarUrl: nil, state: .failed("The upload failed: the server did not answer.")), as: .scaledImage)
    }
}
