import Testing
@testable import Utils

struct ClientIdentityTests {
    @Test func macValuesAreUnchanged() {
        let identity = ClientIdentity(platform: .macOS)

        #expect(identity.deviceDisplayName == "Mactrix")
        #expect(identity.userAgent == "Mactrix macOS")
    }

    @Test func iPhoneValues() {
        let identity = ClientIdentity(platform: .iPhone)

        #expect(identity.deviceDisplayName == "Mactrix (iPhone)")
        #expect(identity.userAgent == "Mactrix iOS")
    }

    @Test func iPadValues() {
        let identity = ClientIdentity(platform: .iPad)

        #expect(identity.deviceDisplayName == "Mactrix (iPad)")
        #expect(identity.userAgent == "Mactrix iOS")
    }

    @Test func everyPlatformHasADistinctDisplayName() {
        let names = Set(ClientPlatform.allCases.map { ClientIdentity(platform: $0).deviceDisplayName })

        #expect(names.count == ClientPlatform.allCases.count)
    }
}
