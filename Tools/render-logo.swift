// Render the OCCA logo: an orienteering control flag on a neutral white background. The white / orange halves are
// split by a curved pen stroke (not the standard straight diagonal), and the "OCCA" wordmark sits in the white part.
// The orange takes about one third of the flag, in the bottom-right corner.
//
// Usage: swift Tools/render-logo.swift <output.png> [size=1024] [wordmark: yes|no] [background: white|clear] [finish: plain|premium]
//        [flag: share of the icon width taken by the flag, default 0.66]
//   App icon (AppIcon, opaque):   swift Tools/render-logo.swift AppIcon-1024.png 1024 yes white
//   In-app logo (AppLogo/AppMark): swift Tools/render-logo.swift AppLogo.png 512 yes white
// Both use the full logo with the "OCCA" wordmark (same as docs/images/occa-logo.png).

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "logo.png"
let S = CGFloat(args.count > 2 ? Double(args[2]) ?? 1024 : 1024)
let wordmark = args.count > 3 ? args[3] == "yes" : true
let clear = args.count > 4 && args[4] == "clear"
/// "premium": gradients, a light edge along the pen stroke, and a top sheen (proposal; the app uses "plain").
let premium = args.count > 5 && args[5] == "premium"
let flagShare = CGFloat(args.count > 6 ? Double(args[6]) ?? 0.66 : 0.66)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1) // y axis down, like screen coordinates

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let orange = rgb(240, 126, 20), white = rgb(255, 255, 255), ink = rgb(30, 32, 31), hairline = rgb(214, 210, 202)

if !clear {
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(255, 255, 255), rgb(242, 242, 240)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: S), options: [])
}

// Flag.
let side = S * flagShare
let box = CGRect(x: S / 2 - side / 2, y: S / 2 - side / 2, width: side, height: side)
let radius = side * 0.10
let flagPath = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

/// Leg of the orange corner along the right and bottom edges (× side): with the stroke's bulge the orange covers
/// about one third of the flag.
let leg: CGFloat = 0.74

/// The pen stroke from the right edge to the bottom edge, bulging toward the white part; `offset` (× side) moves it
/// into the orange corner.
func penCurve(offset: CGFloat) -> [CGPoint] {
    let start = CGPoint(x: box.maxX, y: box.maxY - leg * side), end = CGPoint(x: box.maxX - leg * side, y: box.maxY)
    return (0...200).map { i in
        let t = CGFloat(i) / 200
        let x = start.x + (end.x - start.x) * t, y = start.y + (end.y - start.y) * t
        let b = -0.05 * sin(.pi * t) * side + offset * side
        return CGPoint(x: x + b * 0.7071, y: y + b * 0.7071)
    }
}
func orangePath(offset: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: penCurve(offset: offset))
    p.addLine(to: CGPoint(x: box.maxX + side, y: box.maxY + side))
    p.closeSubpath()
    return p
}

// Shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.06), blur: side * 0.14, color: rgb(0, 0, 0, clear ? 0.18 : 0.22))
ctx.addPath(flagPath)
ctx.setFillColor(white)
ctx.fillPath()
ctx.restoreGState()

// Halves. With the "premium" finish: soft light on the white (white → warm off-white), a rich orange gradient,
// a thin light edge along the pen stroke, and a faint sheen inside the top edge.
ctx.saveGState()
ctx.addPath(flagPath)
ctx.clip()
if premium {
    let whiteGradient = CGGradient(colorsSpace: space, colors: [rgb(255, 255, 255), rgb(243, 240, 234)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(whiteGradient, start: CGPoint(x: box.minX, y: box.minY), end: CGPoint(x: box.maxX, y: box.maxY), options: [])
    ctx.saveGState()
    ctx.addPath(orangePath(offset: 0))
    ctx.clip()
    let orangeGradient = CGGradient(colorsSpace: space, colors: [rgb(250, 146, 40), rgb(240, 126, 20), rgb(222, 100, 10)] as CFArray,
                                    locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(orangeGradient, start: CGPoint(x: box.maxX - side * 0.25, y: box.maxY - side * 0.75),
                           end: CGPoint(x: box.maxX, y: box.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    let edge = CGMutablePath()
    edge.addLines(between: penCurve(offset: 0.006))
    ctx.addPath(edge)
    ctx.setStrokeColor(rgb(255, 214, 170, 0.75))
    ctx.setLineWidth(side * 0.010)
    ctx.setLineCap(.round)
    ctx.strokePath()
    let sheen = CGGradient(colorsSpace: space, colors: [rgb(255, 255, 255, 0.9), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: box.minY), end: CGPoint(x: 0, y: box.minY + side * 0.05), options: [])
} else {
    ctx.setFillColor(white)
    ctx.fill(box)
    ctx.addPath(orangePath(offset: 0))
    ctx.setFillColor(orange)
    ctx.fillPath()
}
ctx.restoreGState()

// Hairline so the white half has an edge on the white background.
ctx.addPath(flagPath)
ctx.setStrokeColor(hairline)
ctx.setLineWidth(max(1, side * 0.008))
ctx.strokePath()

// Wordmark: "OCCA", semibold, tracked, in the white half (top-left).
if wordmark {
    let size = side * 0.15
    let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
    let traits = [kCTFontWeightTrait: 0.3] as CFDictionary
    let font = CTFontCreateCopyWithAttributes(base, size, nil,
                                              CTFontDescriptorCreateWithAttributes([kCTFontTraitsAttribute: traits] as CFDictionary))
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
        NSAttributedString.Key(kCTKernAttributeName as String): side * 0.03,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "OCCA", attributes: attrs))
    ctx.saveGState()
    ctx.translateBy(x: box.minX + side * 0.12, y: box.minY + side * 0.24)   // baseline
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Couldn't write \(outPath)") }
print("Wrote \(outPath) (\(Int(S)) px)")
