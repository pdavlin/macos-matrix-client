import Core
import SwiftUI

/// Placeholder root for the iOS shell (MATRIX-82). It shows the Core session
/// state only. The room list and timeline arrive in MATRIX-84 and MATRIX-85.
struct RootView: View {
    let model: RootViewModel

    var body: some View {
        if let matrixClient = model.appState.matrixClient {
            SignedInRoomNavigation(matrixClient: matrixClient)
        } else {
            signedOut
        }
    }

    private var signedOut: some View {
        ContentUnavailableView {
            Label("Mactrix", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text(model.status.title)
                .accessibilityIdentifier("sessionStatus")
        }
    }
}

#Preview {
    RootView(model: RootViewModel(appState: .init()))
}
