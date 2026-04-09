#!/usr/bin/env swift

import AppKit
import CoreGraphics

let size = 1024

func createIcon(
    gradientStart: (r: CGFloat, g: CGFloat, b: CGFloat),
    gradientEnd: (r: CGFloat, g: CGFloat, b: CGFloat),
    symbolColor: NSColor,
    filename: String
) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Failed to create CGContext")
        return
    }

    // Draw gradient background (top-leading to bottom-trailing)
    let colors = [
        CGColor(red: gradientStart.r, green: gradientStart.g, blue: gradientStart.b, alpha: 1.0),
        CGColor(red: gradientEnd.r, green: gradientEnd.g, blue: gradientEnd.b, alpha: 1.0)
    ] as CFArray

    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) else {
        print("Failed to create gradient")
        return
    }

    // Top-leading to bottom-trailing (note: CGContext has flipped Y)
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(size)),     // top-left
        end: CGPoint(x: CGFloat(size), y: 0),        // bottom-right
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Render SF Symbol "waveform"
    let pointSize: CGFloat = 420
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
    guard let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        print("Failed to load SF Symbol 'waveform'")
        return
    }

    // Create a tinted version of the symbol
    let tintedSymbol = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        symbolColor.set()
        rect.fill(using: .sourceAtop)
        return true
    }

    // Draw the symbol centered on the icon
    let symbolSize = tintedSymbol.size
    let x = (CGFloat(size) - symbolSize.width) / 2
    let y = (CGFloat(size) - symbolSize.height) / 2

    // Use NSGraphicsContext to draw into our CGContext
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    tintedSymbol.draw(
        in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    // Save as PNG
    guard let cgImage = ctx.makeImage() else {
        print("Failed to create CGImage")
        return
    }

    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return
    }

    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(filename)
    do {
        try pngData.write(to: url)
        print("Created: \(filename) (\(size)x\(size))")
    } catch {
        print("Failed to write \(filename): \(error)")
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Light icon: #A78BFA → #7C3AED (matches Dynamic Island)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
createIcon(
    gradientStart: (r: 0.655, g: 0.545, b: 0.980),  // #A78BFA
    gradientEnd:   (r: 0.486, g: 0.228, b: 0.929),   // #7C3AED
    symbolColor: .white,
    filename: "AppIcon-light.png"
)

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Dark icon: #7C3AED → #4C1D95 (deeper purple)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
createIcon(
    gradientStart: (r: 0.486, g: 0.228, b: 0.929),   // #7C3AED
    gradientEnd:   (r: 0.298, g: 0.114, b: 0.584),    // #4C1D95
    symbolColor: .white,
    filename: "AppIcon-dark.png"
)

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Tinted icon: grayscale for iOS 18 automatic tinting
// Medium-gray background, lighter waveform
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
createIcon(
    gradientStart: (r: 0.40, g: 0.40, b: 0.40),
    gradientEnd:   (r: 0.30, g: 0.30, b: 0.30),
    symbolColor: NSColor(white: 0.90, alpha: 1.0),
    filename: "AppIcon-tinted.png"
)

print("\nDone! Move the PNGs into your Assets.xcassets/AppIcon.appiconset/ folder.")
