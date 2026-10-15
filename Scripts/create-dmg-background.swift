import AppKit
import Foundation

enum InstallerArtworkError: Error {
    case invalidArguments
    case bitmapUnavailable
    case pngUnavailable
}

guard CommandLine.arguments.count == 2 else {
    throw InstallerArtworkError.invalidArguments
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvas = NSSize(width: 980, height: 620)
let canvasRect = NSRect(origin: .zero, size: canvas)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas.width),
    pixelsHigh: Int(canvas.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw InstallerArtworkError.bitmapUnavailable
}

bitmap.size = canvas
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func drawText(
    _ value: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .center
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    NSAttributedString(
        string: value,
        attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    ).draw(in: rect)
}

func fillCircle(center: NSPoint, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )).fill()
}

// Original, quietly colourful artwork. It borrows the visual vocabulary of
// LumaView (blue, violet, pink and sunshine) while keeping the real Finder
// app and Applications icons legible and easy to drag.
color(0.971, 0.980, 0.996).setFill()
NSBezierPath(rect: canvasRect).fill()

let upperGlow = NSGradient(colors: [
    color(0.73, 0.91, 1.0, 0.62),
    color(0.87, 0.80, 1.0, 0.31),
    color(1, 1, 1, 0),
])!
upperGlow.draw(
    fromCenter: NSPoint(x: 490, y: 546),
    radius: 0,
    toCenter: NSPoint(x: 490, y: 546),
    radius: 430,
    options: [.drawsAfterEndingLocation]
)

let lowerGlow = NSGradient(colors: [
    color(0.24, 0.77, 0.98, 0.12),
    color(0.73, 0.28, 0.95, 0.08),
    .clear,
])!
lowerGlow.draw(
    fromCenter: NSPoint(x: 490, y: 248),
    radius: 0,
    toCenter: NSPoint(x: 490, y: 248),
    radius: 372,
    options: [.drawsAfterEndingLocation]
)

// Four soft colour notes make the empty space feel like an image canvas, not
// a generic installer backdrop. They intentionally avoid the interaction line.
fillCircle(center: NSPoint(x: 142, y: 517), radius: 22, color: color(0.12, 0.75, 0.95, 0.22))
fillCircle(center: NSPoint(x: 174, y: 487), radius: 12, color: color(0.45, 0.31, 0.96, 0.18))
fillCircle(center: NSPoint(x: 838, y: 515), radius: 25, color: color(1.0, 0.67, 0.08, 0.20))
fillCircle(center: NSPoint(x: 870, y: 486), radius: 13, color: color(0.96, 0.22, 0.55, 0.17))

let markGradient = NSGradient(colors: [
    color(0.08, 0.75, 0.95),
    color(0.36, 0.42, 0.99),
    color(0.92, 0.25, 0.72),
])!
let mark = NSBezierPath(roundedRect: NSRect(x: 427, y: 563, width: 126, height: 5), xRadius: 2.5, yRadius: 2.5)
markGradient.draw(in: mark, angle: 0)

drawText(
    "LumaView",
    in: NSRect(x: 110, y: 511, width: 760, height: 38),
    font: .systemFont(ofSize: 30, weight: .semibold),
    color: color(0.10, 0.13, 0.19)
)
drawText(
    "A brighter way to view your images on macOS",
    in: NSRect(x: 110, y: 478, width: 760, height: 22),
    font: .systemFont(ofSize: 15, weight: .medium),
    color: color(0.29, 0.34, 0.44, 0.80)
)

// The only central instruction graphic: a light, rounded arrow from the app
// to Applications. The real icons and Finder labels supply the rest.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 445, y: 303))
arrow.line(to: NSPoint(x: 528, y: 303))
arrow.lineWidth = 4
arrow.lineCapStyle = .round
color(0.20, 0.24, 0.33, 0.86).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 510, y: 321))
arrowHead.line(to: NSPoint(x: 528, y: 303))
arrowHead.line(to: NSPoint(x: 510, y: 285))
arrowHead.lineWidth = 4
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
color(0.20, 0.24, 0.33, 0.86).setStroke()
arrowHead.stroke()

drawText(
    "Drag LumaView to Applications to install",
    in: NSRect(x: 130, y: 126, width: 720, height: 24),
    font: .systemFont(ofSize: 15, weight: .medium),
    color: color(0.25, 0.30, 0.39, 0.86)
)
drawText(
    "Universal · Intel + Apple Silicon · macOS 13 or later",
    in: NSRect(x: 130, y: 94, width: 720, height: 19),
    font: .systemFont(ofSize: 12, weight: .regular),
    color: color(0.40, 0.45, 0.54, 0.70)
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw InstallerArtworkError.pngUnavailable
}
try png.write(to: outputURL, options: .atomic)
