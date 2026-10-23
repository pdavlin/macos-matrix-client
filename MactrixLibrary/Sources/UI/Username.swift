import Models
import SwiftUI

struct Username<Profile: UserProfile>: View {
    var userProfile: Profile
    /// Overrides the per-user asset color. The timeline header passes the
    /// MATRIX-68 sender palette here; the inspector keeps the default.
    var color: Color?

    var body: some View {
        Text(userProfile.displayName ?? userProfile.userId).foregroundStyle(color ?? Color(userID: userProfile.userId))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(userProfile.displayName ?? userProfile.userId)
            .textSelection(.enabled)
    }
}
