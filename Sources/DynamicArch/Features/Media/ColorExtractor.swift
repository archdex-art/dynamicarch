import AppKit
import CoreImage
import SwiftUI

/// Pulls a usable accent out of album art: average colour, then saturation and
/// brightness pushed into a range that reads well as a glow on black.
enum ColorExtractor {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])
    private static var cache: [Int: Color] = [:]

    static func accent(for image: NSImage) -> Color {
        let key = image.hashValue
        if let cached = cache[key] { return cached }

        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff)
        else { return Palette.accent }

        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]), let output = filter.outputImage else { return Palette.accent }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(output,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        NSColor(red: CGFloat(bitmap[0]) / 255,
                green: CGFloat(bitmap[1]) / 255,
                blue: CGFloat(bitmap[2]) / 255,
                alpha: 1)
            .usingColorSpace(.sRGB)?
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let tuned = NSColor(hue: hue,
                            saturation: min(1, max(0.45, saturation * 1.5)),
                            brightness: min(1, max(0.62, brightness * 1.25)),
                            alpha: 1)
        let color = Color(nsColor: tuned)
        if cache.count > 64 { cache.removeAll(keepingCapacity: true) }
        cache[key] = color
        return color
    }
}
