import Foundation
import ImageIO
import SwiftUI

/// A compact, value-only snapshot of one file's metadata. It is intentionally
/// created only when the inspector is opened: browsing never indexes EXIF or
/// keeps metadata for other files in memory.
struct ImageInformation: Equatable, Sendable {
    let fileName: String
    let fileFormat: String
    let fileSize: Int?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let capturedAt: String?
    let camera: String?
    let lens: String?
    let exposure: String?
    let aperture: String?
    let iso: String?
    let focalLength: String?

    var hasEXIF: Bool {
        [capturedAt, camera, lens, exposure, aperture, iso, focalLength].contains { $0 != nil }
    }

    var dimensions: String? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return "\(pixelWidth) × \(pixelHeight)"
    }

    var formattedFileSize: String? {
        guard let fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}

enum ImageInformationReader {
    /// Image I/O reads the container header and EXIF dictionary without decoding
    /// image pixels. This is the same native metadata path used by the viewer's
    /// dimension probe, but it runs only after an explicit information request.
    static func read(from url: URL) -> ImageInformation {
        let fileValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        let properties = source.flatMap {
            CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any]
        }
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let pixelSize = properties.flatMap { ImageDecoder.orientedPixelSize(from: $0) }

        let make = string(in: tiff, for: kCGImagePropertyTIFFMake)
        let model = string(in: tiff, for: kCGImagePropertyTIFFModel)
        let camera = [make, model].compactMap { $0 }.joined(separator: " ")

        return ImageInformation(
            fileName: url.lastPathComponent,
            fileFormat: displayFormat(for: url),
            fileSize: fileValues?.fileSize,
            pixelWidth: pixelSize.flatMap { Int(exactly: $0.width) },
            pixelHeight: pixelSize.flatMap { Int(exactly: $0.height) },
            capturedAt: formattedCaptureDate(string(in: exif, for: kCGImagePropertyExifDateTimeOriginal)),
            camera: camera.isEmpty ? nil : camera,
            lens: string(in: exif, for: kCGImagePropertyExifLensModel),
            exposure: formattedExposure(number(in: exif, for: kCGImagePropertyExifExposureTime)),
            aperture: formattedAperture(number(in: exif, for: kCGImagePropertyExifFNumber)),
            iso: formattedISO(exif?[kCGImagePropertyExifISOSpeedRatings]),
            focalLength: formattedFocalLength(number(in: exif, for: kCGImagePropertyExifFocalLength))
        )
    }

    private static func string(in dictionary: [CFString: Any]?, for key: CFString) -> String? {
        guard let value = dictionary?[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(in dictionary: [CFString: Any]?, for key: CFString) -> Double? {
        guard let value = dictionary?[key] as? NSNumber else { return nil }
        let number = value.doubleValue
        return number.isFinite && number > 0 ? number : nil
    }

    private static func displayFormat(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "JPEG"
        case "tif", "tiff": return "TIFF"
        case "heic", "heif": return "HEIF"
        case "png": return "PNG"
        case "gif": return "GIF"
        case "webp": return "WebP"
        case "avif": return "AVIF"
        case "pdf": return "PDF"
        default:
            let extensionName = url.pathExtension.uppercased()
            return extensionName.isEmpty ? "—" : extensionName
        }
    }

    private static func formattedCaptureDate(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        // EXIF's locale-independent canonical format is more reliable than
        // guessing a time zone that is not stored in many camera files.
        guard rawValue.count >= 19 else { return rawValue }
        let prefix = rawValue.prefix(19)
        let components = prefix.split(separator: " ", maxSplits: 1)
        guard components.count == 2 else { return rawValue }
        return "\(components[0].replacingOccurrences(of: ":", with: "-")) \(components[1])"
    }

    static func formattedExposure(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        if seconds < 1 {
            let reciprocal = (1 / seconds).rounded()
            guard reciprocal.isFinite else { return "\(String(format: "%.3g", seconds)) s" }
            return "1/\(formattedDecimal(reciprocal)) s"
        }
        return "\(formattedDecimal(seconds)) s"
    }

    private static func formattedAperture(_ aperture: Double?) -> String? {
        aperture.map { "f/\(formattedDecimal($0))" }
    }

    private static func formattedISO(_ rawValue: Any?) -> String? {
        if let values = rawValue as? [NSNumber], let value = values.first, value.intValue > 0 {
            return String(value.intValue)
        }
        if let value = rawValue as? NSNumber, value.intValue > 0 {
            return String(value.intValue)
        }
        return nil
    }

    private static func formattedFocalLength(_ focalLength: Double?) -> String? {
        focalLength.map { "\(formattedDecimal($0)) mm" }
    }

    static func formattedDecimal(_ value: Double) -> String {
        // Metadata is untrusted: finite Double values may still lie outside
        // Int's range. Formatting directly avoids a conversion trap.
        if value.rounded() == value { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}

/// A deliberately compact inspector: general file facts are always available;
/// camera rows appear only when the source really contains EXIF data.
struct ImageInformationInspector: View {
    /// Let compact records stay compact, while keeping long file names and
    /// camera values within a calm, readable upper bound.
    static let maximumPreferredWidth: CGFloat = 340

    let information: ImageInformation
    let l: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l.text("metadata.title"))
                .font(.headline)

            informationSection(
                title: l.text("metadata.fileSection"),
                rows: fileRows(for: information),
                allowsFirstValueWrapping: true
            )

            if information.hasEXIF {
                informationSection(
                    title: l.text("metadata.exifSection"),
                    rows: exifRows(for: information)
                )
            } else {
                Text(l.text("metadata.noExif"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: Self.maximumPreferredWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("image.informationInspector")
    }

    private func informationSection(
        title: String,
        rows: [(String, String)],
        allowsFirstValueWrapping: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        Text(rows[index].0)
                            .foregroundStyle(.secondary)
                        Text(rows[index].1)
                            .textSelection(.enabled)
                            .lineLimit(allowsFirstValueWrapping && index == 0 ? nil : 2)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
        }
    }

    private func fileRows(for information: ImageInformation) -> [(String, String)] {
        compactRows([
            (l.text("metadata.name"), information.fileName),
            (l.text("metadata.format"), information.fileFormat),
            (l.text("metadata.dimensions"), information.dimensions),
            (l.text("metadata.fileSize"), information.formattedFileSize)
        ])
    }

    private func exifRows(for information: ImageInformation) -> [(String, String)] {
        compactRows([
            (l.text("metadata.capturedAt"), information.capturedAt),
            (l.text("metadata.camera"), information.camera),
            (l.text("metadata.lens"), information.lens),
            (l.text("metadata.exposure"), information.exposure),
            (l.text("metadata.aperture"), information.aperture),
            (l.text("metadata.iso"), information.iso),
            (l.text("metadata.focalLength"), information.focalLength)
        ])
    }

    private func compactRows(_ rows: [(String, String?)]) -> [(String, String)] {
        rows.compactMap { label, value in value.map { (label, $0) } }
    }
}
