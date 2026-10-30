import Core
@testable import MactrixiOS
import XCTest

/// MATRIX-89: the pusher values that the Sygnal deployment (MATRIX-90) must match.
final class PushGatewayTests: XCTestCase {
    func testGatewayURL() {
        XCTAssertEqual(PushGateway.url, "https://davlin-matrix.exe.xyz/_matrix/push/v1/notify")
    }

    func testPusherAppIDIsTheAppBundleIdentifier() {
        XCTAssertEqual(PushGateway.pusherAppID, "io.davlin.matrixclient.ios")
        XCTAssertEqual(PushGateway.pusherAppID, Bundle.main.bundleIdentifier)
    }

    func testDefaultPayloadRunsTheExtension() {
        XCTAssertEqual(
            PushGateway.defaultPayload,
            #"{"aps":{"alert":{"body":"New message","title":"Mactrix"},"mutable-content":1}}"#
        )
    }

    @MainActor
    func testLanguageIsNotEmpty() {
        XCTAssertFalse(PushRegistration.language.isEmpty)
    }
}
