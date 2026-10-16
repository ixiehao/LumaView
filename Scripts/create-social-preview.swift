import AppKit
import Foundation

enum SocialPreviewError: Error {
    case invalidArguments
    case unreadableImage(String)
    case unableToCreateBitmap
    case unableToWrite(String)
}

private let canvas = NSSize(width: 1280, height: 640)

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

private func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

private func fill(_ rect: NSRect, color fillColor: NSColor, radius: CGFloat = 0) {
    let path = radius > 0 ? roundedRect(rect, radius: radius) : NSBezierPath(rect: rect)
    fillColor.setFill()
    path.fill()
}

private func stroke(_ rect: NSRect, color strokeColor: NSColor, width: CGFloat = 1, radius: CGFloat = 0) {
    let path = radius > 0 ? roundedRect(rect, radius: radius) : NSBezierPath(rect: rect)
    strokeColor.setStroke()
    path.lineWidth = width
    path.stroke()
}

private func drawText(
    _ value: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color textColor: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    NSAttributedString(
        string: value,
        attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
    ).draw(in: rect)
}

private func drawImageAspectFit(_ image: NSImage, in rect: NSRect) {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return }
    let scale = min(rect.width / size.width, rect.height / size.height)
    let rendered = NSSize(width: size.width * scale, height: size.height * scale)
    image.draw(
        in: NSRect(
            x: rect.midX - rendered.width / 2,
            y: rect.midY - rendered.height / 2,
            width: rendered.width,
            height: rendered.height
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

private func render(screenshot: NSImage, icon: NSImage) throws -> Data {
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
    ) else {
        throw SocialPreviewError.unableToCreateBitmap
    }
    bitmap.size = canvas
    guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw SocialPreviewError.unableToCreateBitmap
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high

    NSGradient(colors: [color(0.018, 0.028, 0.070), color(0.080, 0.040, 0.160)])!
        .draw(in: NSRect(origin: .zero, size: canvas), angle: -24)
    let glow = NSGradient(colors: [color(0.08, 0.72, 0.96, 0.20), color(0.80, 0.20, 0.92, 0.12), .clear])!
    glow.draw(
        fromCenter: NSPoint(x: 970, y: 365), radius: 0,
        toCenter: NSPoint(x: 970, y: 365), radius: 610,
        options: [.drawsAfterEndingLocation]
    )

    let card = NSRect(x: 54, y: 64, width: 1172, height: 512)
    fill(card, color: color(0.018, 0.036, 0.090, 0.80), radius: 30)
    stroke(card, color: color(0.46, 0.74, 1.0, 0.26), width: 1, radius: 30)

    let badge = NSRect(x: 90, y: 493, width: 86, height: 27)
    fill(badge, color: color(0.09, 0.47, 0.84), radius: 13.5)
    drawText("macOS", in: NSRect(x: 90, y: 499, width: 86, height: 14), size: 12, weight: .bold, color: .white, alignment: .center)

    let iconRect = NSRect(x: 90, y: 382, width: 76, height: 76)
    fill(iconRect, color: color(1, 1, 1, 0.08), radius: 18)
    drawImageAspectFit(icon, in: iconRect.insetBy(dx: 5, dy: 5))
    drawText("LumaView", in: NSRect(x: 182, y: 410, width: 270, height: 43), size: 42, weight: .bold, color: color(0.94, 0.97, 1.0))
    drawText("A minimal native image viewer for Mac", in: NSRect(x: 90, y: 338, width: 390, height: 30), size: 21, weight: .semibold, color: color(0.75, 0.87, 1.0))
    drawText("Browse · Zoom · Rotate", in: NSRect(x: 90, y: 297, width: 360, height: 24), size: 17, weight: .medium, color: color(0.57, 0.78, 0.97))
    drawText("macOS 13+ · Intel + Apple Silicon", in: NSRect(x: 90, y: 268, width: 385, height: 19), size: 14, weight: .medium, color: color(0.38, 0.87, 0.92))
    drawText("Open an image. Start browsing.", in: NSRect(x: 90, y: 143, width: 365, height: 25), size: 19, weight: .semibold, color: color(0.82, 0.91, 1.0))
    fill(NSRect(x: 90, y: 116, width: 340, height: 5), color: color(0.10, 0.77, 0.95), radius: 2.5)
    drawText("Local native viewer", in: NSRect(x: 90, y: 92, width: 280, height: 16), size: 13, weight: .medium, color: color(0.52, 0.66, 0.84))

    let screenshotBackdrop = NSRect(x: 540, y: 80, width: 610, height: 480)
    fill(screenshotBackdrop, color: color(0, 0, 0, 0.20), radius: 24)
    let screenshotRect = NSRect(x: 661, y: 80, width: 367, height: 480)
    fill(screenshotRect, color: color(0, 0, 0, 0.28), radius: 22)
    NSGraphicsContext.saveGraphicsState()
    roundedRect(screenshotRect, radius: 22).addClip()
    drawImageAspectFit(screenshot, in: screenshotRect)
    NSGraphicsContext.restoreGraphicsState()
    stroke(screenshotRect, color: color(0.60, 0.88, 1.0, 0.38), width: 1.5, radius: 22)

    NSGraphicsContext.restoreGraphicsState()
    guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.90]) else {
        throw SocialPreviewError.unableToWrite("preview")
    }
    return jpeg
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: create-social-preview.swift <running-app-screenshot> <app-icon> <social-preview.jpg>\\n", stderr)
    throw SocialPreviewError.invalidArguments
}

let screenshotURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let screenshot = NSImage(contentsOf: screenshotURL) else {
    throw SocialPreviewError.unreadableImage(screenshotURL.path)
}
guard let icon = NSImage(contentsOf: iconURL) else {
    throw SocialPreviewError.unreadableImage(iconURL.path)
}

try render(screenshot: screenshot, icon: icon)
    .write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
