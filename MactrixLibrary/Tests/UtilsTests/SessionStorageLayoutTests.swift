import Foundation
import Security
import Testing
@testable import Utils

struct SessionStoreRootsTests {
    private let applicationSupport = URL(filePath: "/Users/u/Library/Application Support", directoryHint: .isDirectory)
    private let caches = URL(filePath: "/Users/u/Library/Caches", directoryHint: .isDirectory)

    @Test func withoutAGroupContainerTheOriginalLayoutIsKept() {
        let roots = SessionStoreRoots.resolve(
            appGroupContainer: nil,
            applicationSupport: applicationSupport,
            caches: caches,
            applicationID: "io.davlin.matrixclient"
        )

        // The Mac layout before MATRIX-88: <Application Support>/<bundle id>/<store id>.
        #expect(roots.data == applicationSupport.appending(component: "io.davlin.matrixclient"))
        #expect(roots.caches == caches.appending(component: "io.davlin.matrixclient"))
        #expect(roots.data.path(percentEncoded: false)
            == "/Users/u/Library/Application Support/io.davlin.matrixclient")
        #expect(roots.caches.path(percentEncoded: false) == "/Users/u/Library/Caches/io.davlin.matrixclient")
        #expect(!roots.isInAppGroupContainer)
    }

    @Test func withAGroupContainerTheStoreIsInTheContainer() {
        let container = URL(filePath: "/private/var/containers/Shared/AppGroup/ABC", directoryHint: .isDirectory)

        let roots = SessionStoreRoots.resolve(
            appGroupContainer: container,
            applicationSupport: applicationSupport,
            caches: caches,
            applicationID: "io.davlin.matrixclient.ios"
        )

        #expect(roots.data.path(percentEncoded: false)
            == "/private/var/containers/Shared/AppGroup/ABC/Library/Application Support/Sessions")
        #expect(roots.caches.path(percentEncoded: false)
            == "/private/var/containers/Shared/AppGroup/ABC/Library/Caches/Sessions")
        #expect(roots.isInAppGroupContainer)
    }

    @Test func theContainerLayoutDoesNotDependOnTheBundleIdentifier() {
        let container = URL(filePath: "/group", directoryHint: .isDirectory)

        let app = SessionStoreRoots.resolve(
            appGroupContainer: container, applicationSupport: applicationSupport, caches: caches,
            applicationID: "io.davlin.matrixclient.ios"
        )
        let ext = SessionStoreRoots.resolve(
            appGroupContainer: container, applicationSupport: applicationSupport, caches: caches,
            applicationID: "io.davlin.matrixclient.ios.nse"
        )

        #expect(app == ext)
    }
}

struct KeychainItemQueryTests {
    private let group = "ABCDE12345.io.davlin.matrixclient.shared"

    @Test func macQueryIsUnchanged() {
        let query = KeychainItemQuery.base(service: "io.davlin.matrixclient", accessGroup: nil, platform: .macOS)

        // The exact attributes of the Mac items before MATRIX-88.
        let expected: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "io.davlin.matrixclient",
            kSecUseDataProtectionKeychain: false,
        ]
        #expect(query as NSDictionary == expected as NSDictionary)
        #expect(KeychainItemQuery.accessibility(platform: .macOS) == kSecAttrAccessibleWhenUnlocked)
    }

    @Test func macQueryIgnoresAnAccessGroup() {
        let query = KeychainItemQuery.base(service: "io.davlin.matrixclient", accessGroup: group, platform: .macOS)

        #expect(query[kSecAttrAccessGroup] == nil)
        #expect(query[kSecUseDataProtectionKeychain] as? Bool == false)
    }

    @Test func iOSQueryCarriesTheSharedGroup() {
        let query = KeychainItemQuery.base(service: "io.davlin.matrixclient.ios", accessGroup: group, platform: .iOS)

        let expected: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "io.davlin.matrixclient.ios",
            kSecAttrAccessGroup: group,
        ]
        #expect(query as NSDictionary == expected as NSDictionary)
    }

    @Test func iOSQueryWithoutAGroupOmitsTheAttribute() {
        let query = KeychainItemQuery.base(service: "io.davlin.matrixclient.ios", accessGroup: nil, platform: .iOS)

        #expect(query[kSecAttrAccessGroup] == nil)
        #expect(query[kSecUseDataProtectionKeychain] == nil)
        #expect(query.count == 2)
    }

    @Test func iOSItemsAreReadableAfterFirstUnlock() {
        #expect(KeychainItemQuery.accessibility(platform: .iOS) == kSecAttrAccessibleAfterFirstUnlock)
    }

    @Test(arguments: [
        ("ABCDE12345.", "ABCDE12345.io.davlin.matrixclient.shared"),
        ("ABCDE12345", "ABCDE12345.io.davlin.matrixclient.shared"),
    ])
    func accessGroupJoinsPrefixAndSuffix(prefix: String, expected: String) {
        #expect(KeychainItemQuery.accessGroup(appIdentifierPrefix: prefix, suffix: "io.davlin.matrixclient.shared")
            == expected)
    }

    @Test(arguments: [nil, ""] as [String?])
    func accessGroupIsNilWithoutAPrefix(prefix: String?) {
        #expect(KeychainItemQuery.accessGroup(appIdentifierPrefix: prefix, suffix: "io.davlin.matrixclient.shared")
            == nil)
    }

    @Test func retriesWithoutAGroupOnlyForAMissingEntitlement() {
        #expect(KeychainItemQuery.shouldRetryWithoutAccessGroup(status: errSecMissingEntitlement, accessGroup: group))
        #expect(errSecMissingEntitlement == -34018)
        #expect(!KeychainItemQuery.shouldRetryWithoutAccessGroup(status: errSecMissingEntitlement, accessGroup: nil))
        #expect(!KeychainItemQuery.shouldRetryWithoutAccessGroup(status: errSecItemNotFound, accessGroup: group))
        #expect(!KeychainItemQuery.shouldRetryWithoutAccessGroup(status: errSecSuccess, accessGroup: group))
    }
}
