import Models
import SwiftUI

/// What an open room shows for the account's membership (MATRIX-104): the
/// cases and wording of the Mac `ChatView.body`.
///
/// Generic over the joined and invited screens, so tests drive it with a
/// fixture membership and fixture screens, without an SDK room.
struct RoomMembershipSwitch<Joined: View, Invited: View>: View {
    let membership: Models.Membership
    let title: String
    private let joined: () -> Joined
    private let invited: () -> Invited

    /// - Parameters:
    ///   - membership: The account's membership in the room.
    ///   - title: The navigation title for every case except `.joined`,
    ///     whose screen sets its own.
    ///   - joined: The timeline screen.
    ///   - invited: The invite screen.
    init(
        membership: Models.Membership,
        title: String,
        @ViewBuilder joined: @escaping () -> Joined,
        @ViewBuilder invited: @escaping () -> Invited
    ) {
        self.membership = membership
        self.title = title
        self.joined = joined
        self.invited = invited
    }

    var body: some View {
        switch membership {
        case .joined:
            joined()
        case .invited:
            invited()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        case .left:
            notice("You have left this room", systemImage: "rectangle.portrait.and.arrow.right")
        case .knocked:
            notice("You have knocked to ask to join this room", systemImage: "hand.raised")
        case .banned:
            notice("You are banned from this room", systemImage: "nosign")
        }
    }

    private func notice(_ text: LocalizedStringKey, systemImage: String) -> some View {
        ContentUnavailableView(text, systemImage: systemImage)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
