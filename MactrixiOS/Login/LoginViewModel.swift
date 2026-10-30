import AuthenticationServices
import Core
import Foundation
import MatrixRustSDK
import Observation
import SwiftUI

/// The sign-in methods one homeserver offers, and the calls that use them.
///
/// The closures hide `HomeserverLogin`, so tests can drive the view model
/// without a homeserver. The live value comes from `LoginService.live`.
struct LoginOptions {
    let supportsPassword: Bool
    let supportsOidc: Bool
    let signInWithPassword: @MainActor (_ username: String, _ password: String) async throws -> Void
    let signInWithOidc: @MainActor (_ session: WebAuthenticationSession) async throws -> Void
}

/// Finds the sign-in methods of a homeserver.
struct LoginService {
    let discover: @MainActor (_ homeserver: String) async throws -> LoginOptions

    /// Drives Core the same way as the Mac `WelcomeSheetView`: discovery
    /// through `MatrixClient.loginDetails`, then `HomeserverLogin` for the
    /// password or OIDC sign-in. `onSignedIn` receives the new client.
    static func live(onSignedIn: @escaping @MainActor (MatrixClient) async -> Void) -> LoginService {
        LoginService { homeserver in
            let login = try await MatrixClient.loginDetails(homeServer: homeserver)
            return LoginOptions(
                supportsPassword: login.loginDetails.supportsPasswordLogin(),
                supportsOidc: login.loginDetails.supportsOidcLogin(),
                signInWithPassword: { username, password in
                    let client = try await login.loginPassword(homeServer: homeserver, username: username, password: password)
                    await onSignedIn(client)
                },
                signInWithOidc: { session in
                    // `WebAuthenticationSession` is the SwiftUI face of
                    // `ASWebAuthenticationSession`. Core's OIDC flow already
                    // takes it, so iOS and macOS share one sign-in path.
                    let client = try await login.loginOidc(webAuthSession: session)
                    await onSignedIn(client)
                }
            )
        }
    }
}

/// Form state for the iOS sign-in screen.
@MainActor @Observable
final class LoginViewModel {
    static let defaultHomeserver = "matrix.org"

    var homeserver = ""
    var username = ""
    var password = ""

    private(set) var options: LoginOptions?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// The homeserver string the current `options` belong to.
    private var discoveredHomeserver: String?

    private let service: LoginService

    init(service: LoginService) {
        self.service = service
    }

    /// The homeserver to contact: the field, or the default if it is empty.
    var effectiveHomeserver: String {
        let trimmed = homeserver.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultHomeserver : trimmed
    }

    var showsPasswordLogin: Bool { options?.supportsPassword == true }
    var showsOidcLogin: Bool { options?.supportsOidc == true }

    /// True when the homeserver answered but offers no method this app supports.
    var hasNoSupportedMethod: Bool {
        guard let options else { return false }
        return !options.supportsPassword && !options.supportsOidc
    }

    var canSubmitPassword: Bool {
        showsPasswordLogin && !isLoading && !username.isEmpty && !password.isEmpty
    }

    /// Call when the homeserver field changes. Old options belong to the old
    /// server and must not sign in against the new one.
    func homeserverDidChange() {
        guard discoveredHomeserver != nil, effectiveHomeserver != discoveredHomeserver else { return }
        options = nil
        discoveredHomeserver = nil
        errorMessage = nil
    }

    func discover() async {
        guard !isLoading else { return }
        let target = effectiveHomeserver
        isLoading = true
        defer { isLoading = false }

        do {
            options = try await service.discover(target)
            discoveredHomeserver = target
            errorMessage = nil
        } catch {
            options = nil
            discoveredHomeserver = nil
            errorMessage = Self.message(for: error)
        }
    }

    func signInWithPassword() async {
        guard canSubmitPassword, let options else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await options.signInWithPassword(username, password)
            password = ""
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func signInWithOidc(using session: WebAuthenticationSession) async {
        guard showsOidcLogin, !isLoading, let options else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await options.signInWithOidc(session)
            errorMessage = nil
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The user closed the browser sheet. That is not an error.
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// The text to show for a sign-in error. Same mapping as the Mac sheet.
    static func message(for error: Error) -> String {
        switch error {
        case let ClientBuildError.InvalidServerName(message: message):
            message
        case let ClientBuildError.ServerUnreachable(message: message):
            message
        default:
            error.localizedDescription
        }
    }
}
