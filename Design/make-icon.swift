// Renders the lens monogram (Design/logo.svg) as the 1024px app icon.
// Run from the repo root:  swift Design/make-icon.swift
// The icon is drawn full-bleed and square; iOS applies the rounded mask itself.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let unit = CGFloat(size) / 200

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

// Match SVG coordinates: origin top-left, 200 units across.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: unit, y: -unit)

func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGRect {
    CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
}

context.setFillColor(color(0x2A2F8F))
context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
context.setFillColor(color(0x5A3FD6))
context.fillEllipse(in: circle(158, 34, 74))
context.setFillColor(color(0x0F8F9C))
context.fillEllipse(in: circle(30, 190, 70))

context.setFillColor(color(0xFFFFFF))
context.addPath(CGPath(roundedRect: CGRect(x: 54, y: 46, width: 24, height: 112), cornerWidth: 12, cornerHeight: 12, transform: nil))
context.fillPath()
context.setStrokeColor(color(0xFFFFFF))
context.setLineWidth(24)
context.strokeEllipse(in: circle(110, 86, 34))
context.setFillColor(color(0x8FE3EA))
context.fillEllipse(in: circle(110, 86, 11))

let output = URL(fileURLWithPath: "Phophy/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(output.path)") }
print("Wrote \(output.path)")
