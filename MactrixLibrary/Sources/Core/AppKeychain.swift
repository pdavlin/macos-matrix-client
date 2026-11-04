import Foundation
import OSLog
import Security
import Utils

public enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

public struct AppKeychain {
    private let service: String
    private let accessGroup: String?
    private let platform: StoragePlatform

    #if os(iOS)
        public init(service: String = AppGroup.keychainService, accessGroup: String? = AppGroup.keychainAccessGroup) {
            self.service = service
            self.accessGroup = accessGroup
            platform = .iOS
        }
    #else
        public init(service: String = Bundle.main.bundleIdentifier!) {
            self.service = service
            accessGroup = nil
            platform = .macOS
        }
    #endif

    private func baseQuery(accessGroup: String?) -> [CFString: Any] {
        KeychainItemQuery.base(service: service, accessGroup: accessGroup, platform: platform)
    }

    /// Runs `body` with the base query. If the build has no entitlement for the
    /// explicit access group (an unsigned simulator build), runs it again
    /// without one.
    private func withBaseQuery<T>(_ body: ([CFString: Any]) throws -> T) throws -> T {
        do {
            return try body(baseQuery(accessGroup: accessGroup))
        } catch let KeychainError.unexpectedStatus(status) {
            guard KeychainItemQuery.shouldRetryWithoutAccessGroup(status: status, accessGroup: accessGroup) else {
                throw KeychainError.unexpectedStatus(status)
            }
            Logger.matrixClient.warning(
                """
                keychain: no entitlement for access group \(accessGroup ?? "", privacy: .public) \
                (\(status)); using the default access group
                """
            )
            return try body(baseQuery(accessGroup: nil))
        }
    }

    /// Saves data for the given key, creating or updating the keychain item.
    public func save(_ data: Data, forKey key: String) throws {
        try withBaseQuery { baseQuery in
            try save(data, forKey: key, baseQuery: baseQuery)
        }
    }

    private func save(_ data: Data, forKey key: String, baseQuery: [CFString: Any]) throws {
        var query = baseQuery
        query[kSecAttrAccount] = key

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData] = data
            query[kSecAttrAccessible] = KeychainItemQuery.accessibility(platform: platform)
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            /// with kSecUseDataProtectionKeychain set to true, this will throw with error -34018, which according to
            /// https://github.com/apple-oss-distributions/Security/blob/09becc8fb155462f0853f99cd09c26b10a38e2f4/sec/Security/SecBasePriv.h#L113
            /// is the error "Internal error when a required entitlement isn't present"
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Returns the data stored for the given key, or `nil` if no item exists.
    public func load(forKey key: String) throws -> Data? {
        try withBaseQuery { baseQuery in
            try load(forKey: key, baseQuery: baseQuery)
        }
    }

    private func load(forKey key: String, baseQuery: [CFString: Any]) throws -> Data? {
        var query = baseQuery
        query[kSecAttrAccount] = key
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = unsafe SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        return result as? Data
    }

    /// Removes all keychain items stored under this service.
    public func removeAll() throws {
        try withBaseQuery { baseQuery in
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }
}
