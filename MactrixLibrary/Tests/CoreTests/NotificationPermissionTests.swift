@testable import Core
import Models
import Testing
import UserNotifications

/// MATRIX-215: the permission that Settings > Notifications shows.
struct NotificationPermissionTests {
    @Test(arguments: [false, true])
    func authorizedIsAllowed(requestFailed: Bool) {
        #expect(NotificationPermissionModel.permission(status: .authorized, requestFailed: requestFailed) == .allowed)
    }

    @Test func provisionalIsAllowed() {
        #expect(NotificationPermissionModel.permission(status: .provisional, requestFailed: false) == .allowed)
    }

    /// The user turned notifications off in System Settings.
    @Test func deniedIsBlocked() {
        #expect(NotificationPermissionModel.permission(status: .denied, requestFailed: false) == .blocked)
    }

    /// Mactrix has not asked yet: no row in Settings.
    @Test func notDeterminedIsUnknown() {
        #expect(NotificationPermissionModel.permission(status: .notDetermined, requestFailed: false) == .unknown)
    }

    /// The request threw (UNErrorDomain code 1): macOS has no answer, but it
    /// blocks every notification.
    @Test func aFailedRequestIsBlocked() {
        #expect(NotificationPermissionModel.permission(status: .notDetermined, requestFailed: true) == .blocked)
    }
}
