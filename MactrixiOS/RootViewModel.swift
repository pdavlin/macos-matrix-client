import Core
import Observation

/// The session state the placeholder root view shows. MATRIX-83 replaces the
/// placeholder with the login and session-restore flow.
enum SessionStatus: Equatable {
    case signedOut
    case signedIn(userID: String)

    init(userID: String?) {
        if let userID {
            self = .signedIn(userID: userID)
        } else {
            self = .signedOut
        }
    }

    var title: String {
        switch self {
        case .signedOut:
            "Signed out"
        case let .signedIn(userID):
            "Signed in as \(userID)"
        }
    }
}

/// Reads login state from Core's `AppState`: signed in when a `MatrixClient`
/// is attached and its session resolves, signed out otherwise.
@MainActor @Observable
final class RootViewModel {
    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var status: SessionStatus {
        SessionStatus(userID: try? appState.matrixClient?.userSession().userID)
    }
}
