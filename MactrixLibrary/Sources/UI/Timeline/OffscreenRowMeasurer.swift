import SwiftUI
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Measures a SwiftUI view offscreen, one view at a time. The timeline's row
/// height cache measures each row it does not know with it, on macOS and on
/// iOS.
///
/// Each measure builds the view's tree in a host, sizes it, and removes it
/// before it returns (MATRIX-220). The host is never on the screen and never
/// draws, so SwiftUI counts every change of an `onChange` or `task(id:)` value
/// in it as a change in one frame. One tree kept across measures gave those
/// modifiers the values of each row in turn: from the third change on,
/// SwiftUI logged "action tried to update multiple times per frame" and
/// dropped the action. The actions it did run worked on rows that are not on
/// the screen, for example a row's `onChange` that gave the Edit menu target
/// of one message to another. A tree that is gone before the run loop
/// dispatches its actions runs none of them: no `onChange`, no `onAppear`, no
/// `task`.
///
/// Usage:
/// ```swift
/// let measurer = OffscreenRowMeasurer()
/// let height = measurer.size(of: rowView, in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
/// ```
@MainActor
public final class OffscreenRowMeasurer {
    #if os(macOS)
        private let host: NSHostingController<AnyView>
    #else
        private let host: UIHostingController<AnyView>
    #endif

    public init() {
        host = .init(rootView: AnyView(EmptyView()))
        #if os(macOS)
            host.sizingOptions = [.preferredContentSize]
        #endif
    }

    /// The size `view` takes when it is offered `proposal`.
    public func size(of view: some View, in proposal: CGSize) -> CGSize {
        host.rootView = AnyView(view)
        let size = host.sizeThatFits(in: proposal)
        // An update with an empty root removes the view's tree now. A new
        // root without an update would only replace the tree at the next
        // measure, and the next view would get this view's modifiers.
        host.rootView = AnyView(EmptyView())
        _ = host.sizeThatFits(in: .zero)
        return size
    }
}
