import AuthenticationServices
import Foundation
import MatrixRustSDK
import OSLog
import SwiftUI
import Utils

public struct HomeserverLogin: Sendable {
    public let storeID: String
    public let storePassphrase: String
    public let unauthenticatedClient: ClientProtocol
    public let loginDetails: HomeserverLoginDetailsProtocol

    public init(
        storeID: String,
        storePassphrase: String,
        unauthenticatedClient: ClientProtocol,
        loginDetails: HomeserverLoginDetailsProtocol
    ) {
        self.storeID = storeID
        self.storePassphrase = storePassphrase
        self.unauthenticatedClient = unauthenticatedClient
        self.loginDetails = loginDetails
    }

    @MainActor
    public func loginPassword(homeServer _: String, username: String, password: String) async throws -> MatrixClient {
        // Login using password authentication.
        try await unauthenticatedClient.login(
            username: username,
            password: password,
            initialDeviceName: ClientIdentity.current.deviceDisplayName,
            deviceId: nil
        )
        return try await onSuccessfullLogin()
    }

    private var oidcConfiguration: OidcConfiguration {
        // redirect uri must be reverse domain of client uri
        OidcConfiguration(clientName: "Mactrix", redirectUri: "com.github:/", clientUri: "https://github.com/viktorstrate/mactrix", logoUri: nil, tosUri: nil, policyUri: nil, staticRegistrations: [:])
    }

    @MainActor
    public func loginOidc(webAuthSession: WebAuthenticationSession) async throws -> MatrixClient {
        Logger.matrixClient.debug("login oidc begin")
        let authInfo = try await unauthenticatedClient.urlForOidc(oidcConfiguration: oidcConfiguration, prompt: .login, loginHint: nil, deviceId: nil, additionalScopes: nil)
        let url = URL(string: authInfo.loginUrl())!

        Logger.matrixClient.debug("Auth url: \(url, privacy: .sensitive)")

        let callbackUrl = try await webAuthSession.authenticate(using: url, callback: .customScheme("com.github"), additionalHeaderFields: [:])

        Logger.matrixClient.debug("after sign in")

        try await unauthenticatedClient.loginWithOidcCallback(callbackUrl: callbackUrl.absoluteString)

        return try await onSuccessfullLogin()
    }

    @MainActor
    fileprivate func onSuccessfullLogin() async throws -> MatrixClient {
        let matrixClient = await MatrixClient(storeID: storeID, storePassphrase: storePassphrase, client: unauthenticatedClient)

        let userSession = try matrixClient.userSession()
        do {
            try userSession.saveUserToKeychain()
        } catch {
            print(error.localizedDescription)
        }

        return matrixClient
    }
}
