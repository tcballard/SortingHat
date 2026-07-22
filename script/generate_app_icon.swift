#!/usr/bin/env swift

import AppKit
import Foundation

private let outputDirectory: URL = {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/SortingHatApp/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
}()

private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
}

private func wizardHat(in rect: CGRect) -> NSBezierPath {
    let path = NSBezierPath()

    // Crooked crown and folded tip. Keep this geometry aligned with
    // WizardHatSilhouette so the app and its icon share one identity.
    path.move(to: point(0.30, 0.68, in: rect))
    path.line(to: point(0.39, 0.28, in: rect))
    path.line(to: point(0.51, 0.22, in: rect))
    path.line(to: point(0.55, 0.05, in: rect))
    path.line(to: point(0.68, 0.00, in: rect))
    path.line(to: point(0.77, 0.18, in: rect))
    path.line(to: point(0.88, 0.10, in: rect))
    path.line(to: point(0.80, 0.29, in: rect))
    path.line(to: point(0.72, 0.25, in: rect))
    path.curve(
        to: point(0.77, 0.68, in: rect),
        controlPoint1: point(0.73, 0.41, in: rect),
        controlPoint2: point(0.79, 0.58, in: rect)
    )
    path.curve(
        to: point(0.30, 0.68, in: rect),
        controlPoint1: point(0.62, 0.73, in: rect),
        controlPoint2: point(0.43, 0.73, in: rect)
    )
    path.close()

    // Uneven hat band.
    path.move(to: point(0.27, 0.64, in: rect))
    path.curve(
        to: point(0.78, 0.67, in: rect),
        controlPoint1: point(0.43, 0.71, in: rect),
        controlPoint2: point(0.64, 0.73, in: rect)
    )
    path.line(to: point(0.75, 0.78, in: rect))
    path.curve(
        to: point(0.26, 0.75, in: rect),
        controlPoint1: point(0.57, 0.83, in: rect),
        controlPoint2: point(0.39, 0.80, in: rect)
    )
    path.close()

    // Wide, swept brim with a nicked trailing edge.
    path.move(to: point(0.03, 0.89, in: rect))
    path.curve(
        to: point(0.29, 0.73, in: rect),
        controlPoint1: point(0.12, 0.83, in: rect),
        controlPoint2: point(0.21, 0.76, in: rect)
    )
    path.curve(
        to: point(0.93, 0.78, in: rect),
        controlPoint1: point(0.50, 0.79, in: rect),
        controlPoint2: point(0.73, 0.70, in: rect)
    )
    path.line(to: point(0.84, 0.89, in: rect))
    path.line(to: point(0.78, 0.87, in: rect))
    path.line(to: point(0.81, 0.95, in: rect))
    path.line(to: point(0.73, 0.90, in: rect))
    path.curve(
        to: point(0.03, 0.89, in: rect),
        controlPoint1: point(0.48, 1.01, in: rect),
        controlPoint2: point(0.25, 0.84, in: rect)
    )
    path.close()

    return path
}

private func renderIcon(size: Int, filename: String) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let ink = NSColor(deviceRed: 0.035, green: 0.055, blue: 0.085, alpha: 1)
    let midnight = NSColor(deviceRed: 0.065, green: 0.09, blue: 0.13, alpha: 1)
    NSGradient(starting: ink, ending: midnight)?.draw(in: canvas, angle: -35)

    // NSBezierPath uses a bottom-left origin; flip to match the SwiftUI shape's
    // top-left-normalized coordinates.
    context.cgContext.translateBy(x: 0, y: CGFloat(size))
    context.cgContext.scaleBy(x: 1, y: -1)

    let inset = CGFloat(size) * 0.14
    let hatRect = CGRect(
        x: inset,
        y: CGFloat(size) * 0.10,
        width: CGFloat(size) - inset * 2,
        height: CGFloat(size) * 0.76
    )
    NSColor(deviceRed: 1.0, green: 0.78, blue: 0.32, alpha: 1).setFill()
    wizardHat(in: hatRect).fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: outputDirectory.appendingPathComponent(filename), options: .atomic)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let renditions = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]
for (size, filename) in renditions {
    try renderIcon(size: size, filename: filename)
}
