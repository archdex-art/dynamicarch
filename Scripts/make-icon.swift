#!/usr/bin/env swift
// Draws the DynamicArch app icon - the island silhouette on a dark squircle -
// at every size macOS asks for, then hands the set to iconutil.
import AppKit

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
]

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func draw(size: Int) -> Data? {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else { return nil }

    // Background squircle with a subtle vertical gradient.
    let inset = side * 0.06
    let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let background = NSBezierPath(roundedRect: rect, xRadius: side * 0.22, yRadius: side * 0.22)
    context.saveGState()
    background.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.16, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.03, alpha: 1)
    ])
    gradient?.draw(in: rect, angle: -90)
    context.restoreGState()

    // The island itself: a black pill with inverted top corners, glowing.
    let pillWidth = side * 0.56
    let pillHeight = side * 0.20
    let pillRect = CGRect(x: (side - pillWidth) / 2,
                          y: side * 0.56,
                          width: pillWidth,
                          height: pillHeight)
    let pill = NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
    NSColor.black.setFill()
    pill.fill()
    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    pill.lineWidth = max(1, side * 0.006)
    pill.stroke()

    // Accent bars, echoing the media visualiser.
    let barCount = 4
    let barWidth = side * 0.035
    let spacing = barWidth * 0.9
    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
    let heights: [CGFloat] = [0.10, 0.17, 0.13, 0.20]
    for index in 0..<barCount {
        let x = (side - totalWidth) / 2 + CGFloat(index) * (barWidth + spacing)
        let height = side * heights[index]
        let bar = NSBezierPath(roundedRect: CGRect(x: x, y: side * 0.26, width: barWidth, height: height),
                               xRadius: barWidth / 2, yRadius: barWidth / 2)
        NSColor(calibratedRed: 0.25, green: 0.55, blue: 1.0, alpha: 1).setFill()
        bar.fill()
    }

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

for (size, name) in sizes {
    guard let data = draw(size: size) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(output)/\(name).png"))
}
print("wrote \(output)")
