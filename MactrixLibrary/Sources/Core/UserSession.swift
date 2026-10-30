import AsyncAlgorithms
import Foundation
import MatrixRustSDK
import OSLog
import Security
import SwiftUI
import UI
import UniformTypeIdentifiers
import Utils

public struct UserSession: Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let userID: String
    public let deviceID: String
    public let homeserverURL: String
    public let oidcData: String?
    public let storeID: String
    public let storePassphrase: String

    public init(session: Session, storeID: String, storePassphrase: String) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        userID = session.userId
        deviceID = session.deviceId
        homeserverURL = session.homeserverUrl
        oidcData = session.oidcData
        self.storeID = storeID
        self.storePassphrase = storePassphrase
    }

    public var session: Session {
        Session(accessToken: accessToken,
                refreshToken: refreshToken,
                userId: userID,
                deviceId: deviceID,
                homeserverUrl: homeserverURL,
                oidcData: oidcData,
                slidingSyncVersion: .native)
    }

    fileprivate static var keychainKey: String { "UserSession" }

    public func saveUserToKeychain() throws {
        let keychainData = try JSONEncoder().encode(self)
        try AppKeychain().save(keychainData, forKey: Self.keychainKey)
    }

    public static func loadUserFromKeychain() throws -> Self? {
        Logger.matrixClient.debug("Load user from keychain")
        if let keychainData = try AppKeychain().load(forKey: keychainKey) {
            return try JSONDecoder().decode(Self.self, from: keychainData)
        }
        return nil
    }
}
