import Core
import SwiftUI

/// Shows the sign-in screen, the launch restore, or the signed-in content.
///
/// The signed-in content gets the verification and recovery banner above it
/// and the verification and recovery sheets.
struct SessionGate<SignedIn: View>: View {
    let session: SessionLifecycle
    @ViewBuilder let signedIn: () -> SignedIn

    @State private var security: SessionSecurityModel

    init(session: SessionLifecycle, @ViewBuilder signedIn: @escaping () -> SignedIn) {
        self.session = session
        self.signedIn = signedIn
        _security = State(initialValue: SessionSecurityModel(appState: session.appState))
    }

    var body: some View {
        Group {
            switch session.phase {
            case .restoring:
                ProgressView("Restoring session…")
                    .accessibilityIdentifier("restoringSession")
            case .signedOut:
                LoginView(model: LoginViewModel(service: .live { client in
                    await session.attach(client)
                }))
            case .signedIn:
                signedIn()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        SessionSecurityBanner(model: security)
                    }
                    .sessionSecuritySheets(model: security)
            }
        }
        .task { await session.restoreOnLaunch() }
        .onChange(of: session.appState.matrixClient?.authenticationFailed) { _, failed in
            if failed == true {
                Task { await session.handleAuthenticationFailure() }
            }
        }
    }
}
