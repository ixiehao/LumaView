import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let canvas = NSSize(width: 1024, height: 1024)
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
    fatalError("Could not create the icon bitmap context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
defer { NSGraphicsContext.restoreGraphicsState() }

let rect = NSRect(origin: .zero, size: canvas)
NSGraphicsContext.current?.imageInterpolation = .high

// Luma Frame: a photo card rests on an L-shaped light rail. The L establishes a
// proprietary memory cue; the card preserves instant “picture viewer” recognition.
NSColor(red: 0.063, green: 0.173, blue: 0.243, alpha: 1).setFill()
rect.fill()

func rounded(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

// A solid, rounded L rather than a second outlined image avoids the generic
// “stacked mountain photo” trope and remains clear at a 32 px Dock size.
let railColor = NSColor(red: 0.18, green: 0.443, blue: 0.502, alpha: 1)
railColor.setFill()
rounded(NSRect(x: 144, y: 174, width: 142, height: 618), radius: 71).fill()
rounded(NSRect(x: 144, y: 174, width: 616, height: 142), radius: 71).fill()

let photo = NSRect(x: 258, y: 286, width: 610, height: 520)
NSColor.white.setFill()
rounded(photo, radius: 145).fill()

let scene = photo.insetBy(dx: 39, dy: 39)
NSGraphicsContext.saveGraphicsState()
rounded(scene, radius: 101).addClip()
NSColor(red: 0.155, green: 0.431, blue: 0.541, alpha: 1).setFill()
scene.fill()

// A warm light and two continuous Bézier waves replace literal, sharp mountains.
NSColor(red: 0.957, green: 0.710, blue: 0.620, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 648, y: 611, width: 112, height: 112)).fill()

let farWave = NSBezierPath()
farWave.move(to: NSPoint(x: 290, y: 505))
farWave.curve(to: NSPoint(x: 522, y: 546), controlPoint1: NSPoint(x: 372, y: 581), controlPoint2: NSPoint(x: 446, y: 586))
farWave.curve(to: NSPoint(x: 830, y: 532), controlPoint1: NSPoint(x: 610, y: 502), controlPoint2: NSPoint(x: 685, y: 468))
farWave.line(to: NSPoint(x: 830, y: 320))
farWave.line(to: NSPoint(x: 290, y: 320))
farWave.close()
NSColor(red: 0.651, green: 0.855, blue: 0.871, alpha: 1).setFill()
farWave.fill()

let frontWave = NSBezierPath()
frontWave.move(to: NSPoint(x: 290, y: 401))
frontWave.curve(to: NSPoint(x: 512, y: 559), controlPoint1: NSPoint(x: 377, y: 438), controlPoint2: NSPoint(x: 435, y: 549))
frontWave.curve(to: NSPoint(x: 710, y: 478), controlPoint1: NSPoint(x: 596, y: 573), controlPoint2: NSPoint(x: 643, y: 486))
frontWave.curve(to: NSPoint(x: 830, y: 525), controlPoint1: NSPoint(x: 768, y: 470), controlPoint2: NSPoint(x: 805, y: 502))
frontWave.line(to: NSPoint(x: 830, y: 320))
frontWave.line(to: NSPoint(x: 290, y: 320))
frontWave.close()
NSColor(red: 0.412, green: 0.784, blue: 0.757, alpha: 1).setFill()
frontWave.fill()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render LumaView app icon")
}
try png.write(to: URL(fileURLWithPath: outputPath))
