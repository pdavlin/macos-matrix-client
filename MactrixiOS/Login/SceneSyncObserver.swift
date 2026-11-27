import Foundation
import UIKit
import Utils

/// MATRIX-242: sends each scene's phase changes to `SessionLifecycle`, from
/// the UIKit scene notifications.
///
/// The notifications name the scene, so on an iPad with several scenes the
/// lifecycle knows the phase of each one, and a scene that iOS disconnects
/// leaves the set. The observer runs each change on the posting thread (the
/// main thread) before the notification returns, so the stop for the
/// background begins its background task before iOS can suspend the app.
///
/// It lives as long as the app: it is made one time, with the root model.
@MainActor
final class SceneSyncObserver {
    private var observers: [any NSObjectProtocol] = []

    private static let changes: [(Notification.Name, SceneSyncLifecycle.Change)] = [
        (UIScene.willEnterForegroundNotification, .entered(.inactive)),
        (UIScene.didActivateNotification, .entered(.active)),
        (UIScene.willDeactivateNotification, .entered(.inactive)),
        (UIScene.didEnterBackgroundNotification, .entered(.background)),
        (UIScene.didDisconnectNotification, .disconnected),
    ]

    init(session: SessionLifecycle) {
        let center = NotificationCenter.default
        for (name, change) in Self.changes {
            let observer = center.addObserver(forName: name, object: nil, queue: nil) { [weak session] notification in
                // A `UIScene` is main-actor isolated, so it can go into the
                // main-actor closure; the notification cannot.
                guard let scene = notification.object as? UIScene else { return }
                MainActor.assumeIsolated {
                    session?.scene(scene.session.persistentIdentifier, did: change)
                }
            }
            observers.append(observer)
        }
    }
}
