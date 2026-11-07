// Render the Cakra Pencil logo: a short hexagonal pencil with white/orange faces (orienteering control flag colors)
// drawing an orange line. The prism geometry is computed in 3D and then projected orthographically, so
// perspective and lighting on each face are consistent.
//
// Usage: swift Tools/render-logo.swift <output.png> [size=1024] [background: white|clear]
// The output is used as the app icon (AppIcon) and the header logo (AppMark).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "logo.png"
let S = CGFloat(args.count > 2 ? Double(args[2]) ?? 1024 : 1024)
let clearBackground = args.count > 3 && args[3] == "clear"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1) // y axis down, like screen coordinates

struct RGB { var r, g, b: Double }
func hex(_ v: UInt32) -> RGB { RGB(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255) }
func color(_ c: RGB, _ k: Double = 1, _ a: Double = 1) -> CGColor {
    CGColor(red: min(c.r * k, 1), green: min(c.g * k, 1), blue: min(c.b * k, 1), alpha: a)
}

if !clearBackground {
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
}

// MARK: 3D geometry

struct V3 { var x, y, z: Double }
func sub(_ a: V3, _ b: V3) -> V3 { V3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
func cross(_ a: V3, _ b: V3) -> V3 { V3(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x) }
func dot(_ a: V3, _ b: V3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
func norm(_ a: V3) -> V3 { let l = sqrt(dot(a, a)); return V3(x: a.x / l, y: a.y / l, z: a.z / l) }
func lerp(_ a: V3, _ b: V3, _ t: Double) -> V3 { V3(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, z: a.z + (b.z - a.z) * t) }

// Rotation: tilt the top end toward the viewer (X axis), then lean to the right (screen Z axis).
let alpha = -62.0 * Double.pi / 180
let gamma = -14.0 * Double.pi / 180
let spinDeg = Double(ProcessInfo.processInfo.environment["LOGO_SPIN"] ?? "") ?? -22
let spin = spinDeg * Double.pi / 180 // spin the prism on its axis so three faces are visible
func rotate(_ p: V3) -> V3 {
    let sx = p.x * cos(spin) - p.y * sin(spin), sy = p.x * sin(spin) + p.y * cos(spin)
    let y1 = sy * cos(alpha) - p.z * sin(alpha), z1 = sy * sin(alpha) + p.z * cos(alpha)
    let x2 = sx * cos(gamma) - y1 * sin(gamma), y2 = sx * sin(gamma) + y1 * cos(gamma)
    return V3(x: x2, y: y2, z: z1)
}

let R = 0.125, H = 0.36, C = 0.19 // hexagon radius, body length, sharpened length (box units)
func hexVertex(_ k: Int, _ z: Double, _ scale: Double = 1) -> V3 {
    let a = Double(k) * Double.pi / 3 + Double.pi / 6
    return V3(x: R * scale * cos(a), y: R * scale * sin(a), z: z)
}
let tip3 = V3(x: 0, y: 0, z: -C)

// Projection + placement: center the pencil's bounding box at (0.52, 0.42).
var projected: [V3] = []
for k in 0..<6 { projected += [rotate(hexVertex(k, 0)), rotate(hexVertex(k, H))] }
projected.append(rotate(tip3))
let minX = projected.map(\.x).min()!, maxX = projected.map(\.x).max()!
let minY = projected.map { -$0.y }.min()!, maxY = projected.map { -$0.y }.max()!
let offX = 0.52 - (minX + maxX) / 2, offY = 0.42 - (minY + maxY) / 2
func screen(_ p: V3) -> CGPoint { let r = rotate(p); return CGPoint(x: (r.x + offX) * Double(S), y: (-r.y + offY) * Double(S)) }

let light = norm(V3(x: -0.55, y: 0.55, z: 0.65))
func shade(_ face: [V3]) -> (visible: Bool, k: Double) {
    let a = rotate(face[0]), b = rotate(face[1]), c = rotate(face[2])
    // Screen y axis is flipped → point order is reversed, so the normal is computed as b−a × c−a and then z is checked.
    let n = norm(cross(sub(b, a), sub(c, a)))
    return (n.z > 0.02, 0.80 + 0.26 * max(0, dot(n, light)))
}

func polygon(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts)
    p.closeSubpath()
    return p
}

// MARK: Shadow and stroke (behind the pencil)

let tipPt = screen(tip3)

ctx.saveGState()
ctx.translateBy(x: tipPt.x + S * 0.04, y: tipPt.y + S * 0.035)
ctx.scaleBy(x: 1, y: 0.22)
let shadow = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.15, green: 0.12, blue: 0.1, alpha: 0.22),
                                                    CGColor(red: 0.15, green: 0.12, blue: 0.1, alpha: 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(shadow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: S * 0.24, options: [])
ctx.restoreGState()

let orange = hex(0xE8641F)
func p(_ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: tipPt.x + dx * Double(S), y: tipPt.y + dy * Double(S)) }
// Stroke as a Catmull-Rom spline (relative to the pencil tip): smooth at every point, ending at the graphite tip.
let knots: [(Double, Double)] = [(0.40, -0.21), (0.17, -0.115), (0.26, -0.03), (0.06, 0.055), (-0.24, 0.065),
                                 (-0.34, 0.005), (-0.22, -0.07), (-0.08, -0.06), (0, 0)]
let pts = knots.map { p($0.0, $0.1) }
let stroke = CGMutablePath()
stroke.move(to: pts[0])
for i in 0..<(pts.count - 1) {
    let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
    stroke.addCurve(to: p2,
                    control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                    control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
}
ctx.addPath(stroke)
ctx.setStrokeColor(color(orange))
ctx.setLineWidth(S * 0.012)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

// MARK: Pencil

// Body faces: alternating white / orange. Filled with a soft gradient across each face (glossy look).
let white = hex(0xF7F3EC)
for k in 0..<6 {
    let face = [hexVertex(k, 0), hexVertex((k + 1) % 6, 0), hexVertex((k + 1) % 6, H), hexVertex(k, H)]
    let s = shade(face)
    guard s.visible else { continue }
    let base = k % 2 == 0 ? white : orange
    let pts = face.map(screen)
    ctx.saveGState()
    ctx.addPath(polygon(pts))
    ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [color(base, s.k * 1.06), color(base, s.k * 0.94)] as CFArray, locations: [0, 1])!
    let e0 = CGPoint(x: (pts[0].x + pts[3].x) / 2, y: (pts[0].y + pts[3].y) / 2)
    let e1 = CGPoint(x: (pts[1].x + pts[2].x) / 2, y: (pts[1].y + pts[2].y) / 2)
    ctx.drawLinearGradient(g, start: e0, end: e1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// Top cap: wood with a thin paint ring, orange core.
let top = (0..<6).map { hexVertex($0, H) }
if shade([top[0], top[1], top[2]]).visible {
    ctx.addPath(polygon(top.map(screen)))
    ctx.setFillColor(color(hex(0xEFD7A8)))
    ctx.fillPath()
    let inner = (0..<6).map { hexVertex($0, H, 0.86) }
    ctx.addPath(polygon(inner.map(screen)))
    ctx.setFillColor(color(hex(0xF6E3BC)))
    ctx.fillPath()
    let core = (0..<48).map { i -> CGPoint in
        let a = Double(i) / 48 * 2 * Double.pi
        return screen(V3(x: R * 0.34 * cos(a), y: R * 0.34 * sin(a), z: H))
    }
    ctx.addPath(polygon(core))
    ctx.setFillColor(color(hex(0xD2541B)))
    ctx.fillPath()
    let coreHi = (0..<48).map { i -> CGPoint in
        let a = Double(i) / 48 * 2 * Double.pi
        return screen(V3(x: R * 0.22 * cos(a) - R * 0.05, y: R * 0.22 * sin(a) + R * 0.03, z: H))
    }
    ctx.addPath(polygon(coreHi))
    ctx.setFillColor(color(hex(0xF0864A)))
    ctx.fillPath()
}

// Sharpened wood: triangles from each hexagon edge to the tip, then the orange core in the last 30%.
let wood = hex(0xEBCB93)
for k in 0..<6 {
    let face = [hexVertex(k, 0), tip3, hexVertex((k + 1) % 6, 0)]
    let s = shade(face)
    guard s.visible else { continue }
    ctx.addPath(polygon(face.map(screen)))
    ctx.setFillColor(color(wood, s.k))
    ctx.fillPath()
    let lead = [lerp(tip3, face[0], 0.3), tip3, lerp(tip3, face[2], 0.3)]
    ctx.addPath(polygon(lead.map(screen)))
    ctx.setFillColor(color(hex(0xD2541B), s.k))
    ctx.fillPath()
}
// Wavy sharpened edge: small arcs along the paint → wood boundary on the visible faces.
for k in 0..<6 {
    let face = [hexVertex(k, 0), hexVertex((k + 1) % 6, 0), hexVertex((k + 1) % 6, H), hexVertex(k, H)]
    let s = shade(face)
    guard s.visible else { continue }
    let a = screen(face[0]), b = screen(face[1])
    let mid = screen(lerp(lerp(face[0], face[1], 0.5), tip3, 0.16))
    let scallop = CGMutablePath()
    scallop.move(to: a)
    scallop.addQuadCurve(to: b, control: mid)
    scallop.closeSubpath()
    ctx.addPath(scallop)
    ctx.setFillColor(color(k % 2 == 0 ? white : orange, s.k))
    ctx.fillPath()
}

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Failed to write \(outPath)") }
print("Logo written to \(outPath) (\(Int(S)) px)")
