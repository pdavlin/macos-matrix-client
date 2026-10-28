#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Platform type aliases so shared views name one type on macOS and iOS.
///
/// macOS keeps the AppKit types unchanged. iOS maps them to their UIKit
/// counterparts.
#if canImport(AppKit)
    public typealias PlatformColor = NSColor
    public typealias PlatformFont = NSFont
    public typealias PlatformImage = NSImage
#elseif canImport(UIKit)
    public typealias PlatformColor = UIColor
    public typealias PlatformFont = UIFont
    public typealias PlatformImage = UIImage

    /// AppKit system color names on iOS, so call sites read the same on both
    /// platforms. Each maps to the closest UIKit semantic color.
    public extension UIColor {
        /// AppKit's `controlBackgroundColor`: white in light mode, near-black in
        /// dark mode.
        static var controlBackgroundColor: UIColor { .secondarySystemGroupedBackground }

        /// AppKit's `separatorColor`.
        static var separatorColor: UIColor { .separator }
    }
#endif
