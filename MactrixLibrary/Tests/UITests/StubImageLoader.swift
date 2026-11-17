import AppKit
import SwiftUI
import UI

/// Fixed sRGB colors for the images that the stub loaders serve.
///
/// Do not use `NSColor.systemGreen` and its siblings in a snapshot test. They
/// are dynamic: the RGB value depends on the appearance that is current when
/// the color resolves (light or dark, and the accessibility contrast). A stub
/// image that draws outside the view tree (a text attachment, for example)
/// resolves it against the system appearance, not against the `.aqua` that the
/// test pins on the view. The reference then holds the state of the Mac at
/// record time.
///
/// The values are those of the system colors in the light appearance, so the
/// references recorded before this file did not change.
extension NSColor {
    static let stubGreen = NSColor(srgbRed: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1)
    static let stubOrange = NSColor(srgbRed: 255 / 255, green: 141 / 255, blue: 40 / 255, alpha: 1)
    static let stubPurple = NSColor(srgbRed: 203 / 255, green: 48 / 255, blue: 224 / 255, alpha: 1)
    static let stubTeal = NSColor(srgbRed: 0 / 255, green: 195 / 255, blue: 208 / 255, alpha: 1)
    static let stubPink = NSColor(srgbRed: 255 / 255, green: 45 / 255, blue: 85 / 255, alpha: 1)
    static let stubBlue = NSColor(srgbRed: 0 / 255, green: 136 / 255, blue: 255 / 255, alpha: 1)
}

/// Solid-color stub images, drawn one time into an sRGB bitmap.
///
/// A bitmap holds its pixels from the moment it is made. An `NSImage` with a
/// drawing handler draws again at each use, with the appearance and the
/// destination of that moment.
enum StubImage {
    enum Shape {
        case square
        case disc
    }

    /// The bitmap has `pixelsPerPoint` pixels for each point of `side`.
    static func make(_ color: NSColor, side: Int, shape: Shape = .square, pixelsPerPoint: Int = 4) -> NSImage {
        let pixels = side * pixelsPerPoint
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let fill = color.usingColorSpace(.sRGB),
            let context = CGContext(
                data: nil,
                width: pixels,
                height: pixels,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            preconditionFailure("Could not make an sRGB bitmap of \(pixels) pixels")
        }

        let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        context.setFillColor(
            red: fill.redComponent,
            green: fill.greenComponent,
            blue: fill.blueComponent,
            alpha: fill.alphaComponent
        )
        switch shape {
        case .square: context.fill(rect)
        case .disc: context.fillEllipse(in: rect)
        }

        guard let bitmap = context.makeImage() else {
            preconditionFailure("Could not make an image from the sRGB bitmap")
        }
        return NSImage(cgImage: bitmap, size: NSSize(width: side, height: side))
    }
}

/// Serves a solid-color image for each known URL, from the cache.
struct StubImageLoader: ImageLoader {
    let colors: [String: NSColor]
    var side = 32
    var shape = StubImage.Shape.square

    func cachedImage(matrixUrl: String) -> Image? {
        guard let color = colors[matrixUrl] else { return nil }
        return Image(nsImage: StubImage.make(color, side: side, shape: shape))
    }

    func loadImage(matrixUrl: String, size _: CGSize?) async throws -> Image? {
        cachedImage(matrixUrl: matrixUrl)
    }
}
