import Testing
@testable import Utils

struct ClientIdentityTests {
    @Test func macValuesAreUnchanged() {
        let identity = ClientIdentity(platform: .macOS)

        #expect(identity.deviceDisplayName == "Round")
        #expect(identity.userAgent == "Round macOS")
    }

    @Test func iPhoneValues() {
        let identity = ClientIdentity(platform: .iPhone)

        #expect(identity.deviceDisplayName == "Round (iPhone)")
        #expect(identity.userAgent == "Round iOS")
    }

    @Test func iPadValues() {
        let identity = ClientIdentity(platform: .iPad)

        #expect(identity.deviceDisplayName == "Round (iPad)")
        #expect(identity.userAgent == "Round iOS")
    }

    @Test func everyPlatformHasADistinctDisplayName() {
        let names = Set(ClientDevice.allCases.map { ClientIdentity(platform: $0).deviceDisplayName })

        #expect(names.count == ClientDevice.allCases.count)
    }
}
