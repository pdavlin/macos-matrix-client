// Builds a contact sheet PNG from ictool renders.
// Usage: swift contact-sheet.swift <out.png> <cell-px> --row <label> <png>... [--row <label> <png>...]
// A file name that ends in "-<Rendition>.png" gets that rendition as its column label.
// A render smaller than half the cell is drawn at 1x and again at 4x (no smoothing).
// An argument "a.png+b.png+c.png" is one cell that shows those renders side by side at 1x.
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 4, let cell = Int(args[1]) else {
    FileHandle.standardError.write(Data("usage: contact-sheet.swift <out.png> <cell-px> --row <label> <png>...\n".utf8))
    exit(2)
}

let outPath = args[0]

struct Row {
    let label: String
    var images: [String]
}

var rows: [Row] = []
var index = 2
while index < args.count {
    if args[index] == "--row", index + 1 < args.count {
        rows.append(Row(label: args[index + 1], images: []))
        index += 2
    } else {
        if rows.isEmpty { rows.append(Row(label: "", images: [])) }
        rows[rows.count - 1].images.append(args[index])
        index += 1
    }
}

let pad = 16
let labelHeight = 28
let rowLabelWidth = 200
let columns = rows.map(\.images.count).max() ?? 0
let width = rowLabelWidth + columns * (cell + pad) + pad
let height = pad + rows.count * (cell + labelHeight + pad)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else {
    exit(1)
}

rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

NSColor(white: 0.96, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

func isDark(_ name: String) -> Bool {
    name.hasSuffix("Dark.png")
}

func columnLabel(_ path: String) -> String {
    let base = (path as NSString).lastPathComponent.replacingOccurrences(of: ".png", with: "")
    return base.components(separatedBy: "-").last ?? base
}

let labelAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(white: 0.2, alpha: 1)
]
let rowAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
    .foregroundColor: NSColor(white: 0.1, alpha: 1)
]

/// Draws renders at 1x, left to right on one baseline, with their pixel sizes under them.
func drawActualSizes(_ paths: [String], in frame: NSRect) {
    let images = paths.compactMap { NSImage(contentsOfFile: $0) }
    let sizes = images.map { image -> CGFloat in
        CGFloat(image.representations.first?.pixelsWide ?? 0)
    }
    let gap: CGFloat = 20
    let total = sizes.reduce(0, +) + gap * CGFloat(max(sizes.count - 1, 0))
    var x = (frame.midX - total / 2).rounded()
    let baseline = (frame.midY - 32).rounded()
    context.imageInterpolation = .none
    for (image, size) in zip(images, sizes) {
        image.draw(in: NSRect(x: x, y: baseline, width: size, height: size))
        ("\(Int(size))" as NSString).draw(at: NSPoint(x: x, y: baseline - 24), withAttributes: labelAttributes)
        x += size + gap
    }
    context.imageInterpolation = .high
    ("1x" as NSString).draw(
        at: NSPoint(x: frame.minX + 4, y: frame.minY - CGFloat(labelHeight) + 6), withAttributes: labelAttributes
    )
}

for (rowIndex, row) in rows.enumerated() {
    let top = height - pad - rowIndex * (cell + labelHeight + pad)
    let cellBottom = top - cell
    (row.label as NSString).draw(
        at: NSPoint(x: pad, y: cellBottom + cell / 2 - 10), withAttributes: rowAttributes
    )
    for (columnIndex, path) in row.images.enumerated() {
        let x = rowLabelWidth + columnIndex * (cell + pad)
        let frame = NSRect(x: x, y: cellBottom, width: cell, height: cell)
        (isDark(path) ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.86, alpha: 1)).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).fill()
        if path.contains("+") {
            drawActualSizes(path.components(separatedBy: "+"), in: frame)
            continue
        }
        guard let image = NSImage(contentsOfFile: path),
              let bitmap = image.representations.first else { continue }
        let w = CGFloat(bitmap.pixelsWide)
        let h = CGFloat(bitmap.pixelsHigh)
        if Int(w) * 2 < cell {
            context.imageInterpolation = .none
            let big = NSRect(x: frame.midX - w * 2 + 24, y: frame.midY - h * 2, width: w * 4, height: h * 4)
            image.draw(in: big)
            image.draw(in: NSRect(x: frame.minX + 16, y: frame.midY - h / 2, width: w, height: h))
            context.imageInterpolation = .high
        } else {
            let inset = CGFloat(cell) * 0.04
            image.draw(in: frame.insetBy(dx: inset, dy: inset))
        }
        (columnLabel(path) as NSString).draw(
            at: NSPoint(x: frame.minX + 4, y: CGFloat(cellBottom - labelHeight + 6)), withAttributes: labelAttributes
        )
    }
}

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
    exit(1)
}
