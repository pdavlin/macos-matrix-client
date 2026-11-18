#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// A block quote in a message body (MATRIX-192): its lines indent, and its
/// text has the secondary text color. Opaque body content, not glass.
public enum BlockQuoteToken {
    /// The indent of each line of a quote, as a part of the body font size.
    public static let indentScale: CGFloat = 1

    /// The color of the quote text. It resolves when the text draws, so it
    /// follows light and dark mode.
    public static var textColor: PlatformColor {
        #if canImport(AppKit)
            .secondaryLabelColor
        #else
            .secondaryLabel
        #endif
    }
}
