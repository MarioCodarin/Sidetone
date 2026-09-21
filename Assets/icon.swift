import AppKit

// Sidetone app icon — rendered headlessly with pure AppKit / Core Graphics.
// Run via ./make-icon.sh.
//
// Design: a dark squircle, a circle split left (green / them) and right (blue / you),
// ringed in a thin red record stroke. Reads as "two channels, one take" down to 16 px.

let S = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
let cs = CGColorSpaceCreateDeviceRGB()

let rect = NSRect(x: 0, y: 0, width: S, height: S)
let radius = S * 0.2237
NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()

let bg = CGGradient(colorsSpace: cs, colors: [
    NSColor(srgbRed: 0.10, green: 0.12, blue: 0.16, alpha: 1).cgColor,
    NSColor(srgbRed: 0.04, green: 0.05, blue: 0.07, alpha: 1).cgColor] as CFArray,
    locations: [0, 1])!
cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

let center = CGPoint(x: S/2, y: S/2)

let glow = CGGradient(colorsSpace: cs, colors: [
    NSColor(srgbRed: 0.20, green: 0.28, blue: 0.36, alpha: 0.45).cgColor,
    NSColor(srgbRed: 0.20, green: 0.28, blue: 0.36, alpha: 0.0).cgColor] as CFArray,
    locations: [0, 1])!
cg.drawRadialGradient(glow, startCenter: center, startRadius: 0,
    endCenter: center, endRadius: S * 0.42, options: [])

let discR = S * 0.30
let discRect = CGRect(x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2)

cg.saveGState()
cg.addEllipse(in: discRect)
cg.clip()

let left = CGGradient(colorsSpace: cs, colors: [
    NSColor(srgbRed: 0.42, green: 0.86, blue: 0.62, alpha: 1).cgColor,
    NSColor(srgbRed: 0.18, green: 0.62, blue: 0.42, alpha: 1).cgColor] as CFArray,
    locations: [0, 1])!
cg.drawLinearGradient(left, start: CGPoint(x: discRect.minX, y: center.y + discR),
    end: CGPoint(x: discRect.minX, y: center.y - discR), options: [])

let rightRect = CGRect(x: center.x, y: discRect.minY, width: discR, height: discR * 2)
cg.saveGState()
cg.clip(to: rightRect)
let right = CGGradient(colorsSpace: cs, colors: [
    NSColor(srgbRed: 0.45, green: 0.72, blue: 1.0, alpha: 1).cgColor,
    NSColor(srgbRed: 0.18, green: 0.40, blue: 0.86, alpha: 1).cgColor] as CFArray,
    locations: [0, 1])!
cg.drawLinearGradient(right, start: CGPoint(x: center.x, y: center.y + discR),
    end: CGPoint(x: center.x, y: center.y - discR), options: [])
cg.restoreGState()
cg.restoreGState()

let ringLineWidth = S * 0.048
let ringRadius = S * 0.30
let ringRect = CGRect(x: center.x - ringRadius, y: center.y - ringRadius,
    width: ringRadius * 2, height: ringRadius * 2)

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -8),
    blur: 22, color: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45).cgColor)
let ringPath = CGMutablePath()
ringPath.addEllipse(in: ringRect)
cg.addPath(ringPath)
cg.setStrokeColor(NSColor(srgbRed: 0.93, green: 0.22, blue: 0.28, alpha: 1).cgColor)
cg.setLineWidth(ringLineWidth)
cg.strokePath()
cg.restoreGState()

let topGlow = CGGradient(colorsSpace: cs, colors: [
    NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.10).cgColor,
    NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.0).cgColor] as CFArray,
    locations: [0, 1])!
cg.drawLinearGradient(topGlow, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: S * 0.72), options: [])

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Sidetone-1024.png"))
print("wrote Sidetone-1024.png")
