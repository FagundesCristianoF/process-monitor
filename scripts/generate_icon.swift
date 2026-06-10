#!/usr/bin/env swift
import AppKit
import CoreGraphics

func generateIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }

    ctx.saveGState()

    // ── Background ────────────────────────────────────────────────
    let radius = s * 0.225
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bg = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bg)

    // Dark gradient bg: deep navy to near-black
    let bgGrad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1),
            CGColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.clip()
    ctx.drawLinearGradient(bgGrad,
        start: CGPoint(x: s * 0.5, y: s),
        end: CGPoint(x: s * 0.5, y: 0),
        options: [])
    ctx.resetClip()

    // ── Activity bars ─────────────────────────────────────────────
    // 5 bars representing process memory/cpu activity
    let barHeights: [CGFloat] = [0.30, 0.55, 0.75, 0.45, 0.62]
    let barCount = barHeights.count
    let totalBarWidth = s * 0.56
    let barW = totalBarWidth / CGFloat(barCount) * 0.62
    let barGap = totalBarWidth / CGFloat(barCount) * 0.38
    let startX = (s - totalBarWidth) / 2 + barW / 2
    let baseY = s * 0.20
    let maxH = s * 0.56
    let barR = barW * 0.40

    for (i, heightFraction) in barHeights.enumerated() {
        let x = startX + CGFloat(i) * (barW + barGap)
        let barH = maxH * heightFraction
        let barRect = CGRect(x: x - barW / 2, y: baseY, width: barW, height: barH)
        let path = CGPath(roundedRect: barRect, cornerWidth: barR, cornerHeight: barR, transform: nil)

        // Color gradient per bar: teal → blue-green
        let t = CGFloat(i) / CGFloat(barCount - 1)
        let r = 0.10 + t * 0.05
        let g = 0.72 - t * 0.12
        let b = 0.80 - t * 0.10

        // Bar glow
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setShadow(offset: .zero, blur: s * 0.04,
            color: CGColor(red: r, green: g, blue: b, alpha: 0.7))
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1.0))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // ── Subtle inner highlight stroke on bg ──────────────────────
    ctx.addPath(bg)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.06))
    ctx.setLineWidth(s * 0.008)
    ctx.strokePath()

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { fatalError("Failed to convert image at \(path)") }
    try! png.write(to: URL(fileURLWithPath: path))
}

// Build iconset
let iconsetPath = "/Users/cristianofagundes/Projects/ProcessMonitor/ProcessMonitor/Resources/AppIcon.iconset"
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",     128),
    ("icon_128x128@2x.png",  256),
    ("icon_256x256.png",     256),
    ("icon_256x256@2x.png",  512),
    ("icon_512x512.png",     512),
    ("icon_512x512@2x.png",  1024),
]

for entry in sizes {
    let img = generateIcon(size: entry.px)
    let path = "\(iconsetPath)/\(entry.name)"
    savePNG(img, to: path)
    print("✓ \(entry.name) (\(entry.px)px)")
}
print("Done. Run: iconutil -c icns \(iconsetPath)")
