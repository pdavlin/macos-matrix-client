#if os(macOS)
    import AppKit
    import Models
    import SwiftUI

    /// Holds a window's content to the width of the screens (MATRIX-266).
    ///
    /// A SwiftUI window grows when its content's minimum width grows. A
    /// layout loop that raises the minimum on each pass made the main window
    /// 14,774 pt wide before AppKit stopped it. Behind this frame the window
    /// gets no wider than every screen together, whatever the content
    /// asks for. A normal window is never that wide, so the frame changes
    /// nothing in normal use.
    ///
    /// The limit follows the screens: it is read again when a display is
    /// added, removed, or rearranged.
    public struct ScreenWidthLimit: ViewModifier {
        private let screenFrames: @MainActor () -> [CGRect]
        @State private var limit: Double?

        /// - Parameter screenFrames: the frames of the screens. Tests give
        ///   fixed frames.
        @MainActor
        public init(screenFrames: @escaping @MainActor () -> [CGRect] = { NSScreen.screens.map(\.frame) }) {
            self.screenFrames = screenFrames
            _limit = State(initialValue: MainWindowLayout.maximumContentWidth(screenFrames: screenFrames()))
        }

        public func body(content: Content) -> some View {
            content
                .frame(maxWidth: limit.map { CGFloat($0) } ?? .infinity)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                    limit = MainWindowLayout.maximumContentWidth(screenFrames: screenFrames())
                }
        }
    }
#endif
