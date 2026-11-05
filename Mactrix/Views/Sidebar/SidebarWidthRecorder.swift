import Foundation
import Models

/// Reads and stores the main window's sidebar width (MATRIX-116, D-8).
///
/// The sidebar reports its width on every geometry change. The recorder
/// stores a width only when it has stayed the same for `settleDelay`. A
/// divider drag stores where it stops; a collapse animation, which passes
/// through many widths and ends below the minimum, stores nothing.
///
/// It writes straight to `UserDefaults`, not through `@AppStorage`: an
/// observed value would re-render the sidebar on each frame of a drag.
@MainActor
final class SidebarWidthRecorder {
    /// How long a width must hold before it is stored.
    static let settleDelay: Duration = .milliseconds(400)

    private let minimumWidth: Double
    private let defaults: UserDefaults
    private var pendingStore: Task<Void, Never>?

    /// - Parameters:
    ///   - minimumWidth: the column's minimum width. Narrower widths are not
    ///     stored.
    ///   - defaults: where the width lives.
    init(minimumWidth: Double, defaults: UserDefaults = .standard) {
        self.minimumWidth = minimumWidth
        self.defaults = defaults
    }

    private var storedWidth: Double? {
        Self.storedWidth(in: defaults)
    }

    private static func storedWidth(in defaults: UserDefaults) -> Double? {
        defaults.object(forKey: SidebarWidthMemory.storageKey) as? Double
    }

    /// The width a new sidebar starts at.
    ///
    /// - Parameters:
    ///   - minimumWidth: the column's minimum width.
    ///   - defaultWidth: the width when nothing usable is stored.
    ///   - defaults: where the width lives.
    static func idealWidth(minimumWidth: Double, defaultWidth: Double, defaults: UserDefaults = .standard) -> Double {
        SidebarWidthMemory.idealWidth(stored: storedWidth(in: defaults), minimum: minimumWidth, defaultIdeal: defaultWidth)
    }

    /// Takes a measured width. The last width reported stores once it has
    /// held for `settleDelay`.
    func record(_ width: Double) {
        pendingStore?.cancel()
        pendingStore = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard
                !Task.isCancelled,
                let self,
                let width = SidebarWidthMemory.widthToStore(measured: width, minimum: minimumWidth, current: storedWidth)
            else { return }
            defaults.set(width, forKey: SidebarWidthMemory.storageKey)
        }
    }
}
