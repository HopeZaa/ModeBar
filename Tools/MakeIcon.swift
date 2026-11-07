// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 HopeZaa

import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

func tile(_ centerY: CGFloat, _ color: NSColor) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 288, y: centerY + 40))
    path.line(to: NSPoint(x: 476, y: centerY + 146))
    path.curve(to: NSPoint(x: 548, y: centerY + 146), controlPoint1: NSPoint(x: 500, y: centerY + 160), controlPoint2: NSPoint(x: 524, y: centerY + 160))
    path.line(to: NSPoint(x: 736, y: centerY + 40))
    path.curve(to: NSPoint(x: 736, y: centerY - 40), controlPoint1: NSPoint(x: 780, y: centerY + 16), controlPoint2: NSPoint(x: 780, y: centerY - 16))
    path.line(to: NSPoint(x: 548, y: centerY - 146))
    path.curve(to: NSPoint(x: 476, y: centerY - 146), controlPoint1: NSPoint(x: 524, y: centerY - 160), controlPoint2: NSPoint(x: 500, y: centerY - 160))
    path.line(to: NSPoint(x: 288, y: centerY - 40))
    path.curve(to: NSPoint(x: 288, y: centerY + 40), controlPoint1: NSPoint(x: 244, y: centerY - 16), controlPoint2: NSPoint(x: 244, y: centerY + 16))
    path.close()
    NSGradient(starting: color, ending: color.blended(withFraction: 0.22, of: .black)!)!.draw(in: path, angle: -60)
    NSColor.white.withAlphaComponent(0.3).setStroke()
    path.lineWidth = 2
    path.stroke()
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    let bg = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 195, yRadius: 195)
    NSGradient(starting: NSColor(srgbRed: 0.19, green: 0.23, blue: 0.36, alpha: 1), ending: NSColor(srgbRed: 0.055, green: 0.07, blue: 0.13, alpha: 1))!.draw(in: bg, angle: -90)
    tile(369, NSColor(srgbRed: 0.48, green: 0.48, blue: 0.92, alpha: 1))
    tile(505, NSColor(srgbRed: 0.40, green: 0.68, blue: 0.96, alpha: 1))
    tile(641, NSColor(srgbRed: 0.61, green: 0.91, blue: 0.96, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(filename))
}
