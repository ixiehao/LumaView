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

private func fill(_ rect: NSRect, color fillColor: NSColor, radius: CGFloat = 0) {
    let path = radius > 0
        ? NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        : NSBezierPath(rect: rect)
    fillColor.setFill()
    path.fill()
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

    // Editorial canvas: no background panels, glows, or synthetic device frame.
    // The UI on the right is drawn directly from the captured LumaView runtime.
    fill(NSRect(origin: .zero, size: canvas), color: color(0.985, 0.984, 0.976))

    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: 680, y: 84))
    divider.line(to: NSPoint(x: 680, y: 556))
    divider.lineWidth = 1
    color(0.87, 0.87, 0.84).setStroke()
    divider.stroke()

    drawImageAspectFit(icon, in: NSRect(x: 92, y: 428, width: 42, height: 42))
    drawText(
        "NATIVE IMAGE VIEWER FOR MAC",
        in: NSRect(x: 148, y: 440, width: 390, height: 17),
        size: 13,
        weight: .semibold,
        color: color(0.28, 0.32, 0.37)
    )
    drawText(
        "LumaView",
        in: NSRect(x: 90, y: 347, width: 510, height: 67),
        size: 56,
        weight: .bold,
        color: color(0.09, 0.11, 0.14)
    )
    drawText(
        "A minimal, native image viewer for Mac.",
        in: NSRect(x: 92, y: 303, width: 500, height: 29),
        size: 21,
        weight: .medium,
        color: color(0.23, 0.27, 0.31)
    )
    drawText(
        "Browse · Zoom · Rotate",
        in: NSRect(x: 92, y: 251, width: 360, height: 24),
        size: 17,
        weight: .medium,
        color: color(0.08, 0.46, 0.73)
    )
    drawText(
        "macOS 12+  ·  Intel + Apple Silicon",
        in: NSRect(x: 92, y: 126, width: 370, height: 18),
        size: 13,
        weight: .medium,
        color: color(0.40, 0.43, 0.46)
    )

    // Keep every pixel of the real app capture visible: no crop, mask, or invented frame.
    drawImageAspectFit(screenshot, in: NSRect(x: 779, y: 50, width: 408, height: 540))

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
