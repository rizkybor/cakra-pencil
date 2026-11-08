import CoreGraphics
import Foundation

/// A single drawing element of an OCAD point symbol, in paper mm relative to the symbol center (x right, y up).
public struct PointElement: Codable, Hashable, Sendable {
    public enum Kind: Int, Codable, Sendable {
        case line = 1, area = 2, circle = 3, dot = 4
    }

    public var kind: Kind
    public var colorHex: String
    /// Color order in the OCAD color table; smaller number = drawn on top.
    public var priority: Int
    public var lineWidthMM: Double
    public var diameterMM: Double
    public var points: [Point2D]

    public init(kind: Kind, colorHex: String, priority: Int, lineWidthMM: Double, diameterMM: Double, points: [Point2D]) {
        self.kind = kind
        self.colorHex = colorHex
        self.priority = priority
        self.lineWidthMM = lineWidthMM
        self.diameterMM = diameterMM
        self.points = points
    }

    /// Outermost radius of the element (mm), for the symbol size and selection area.
    public var extentMM: Double {
        switch kind {
        case .dot: return diameterMM / 2
        case .circle: return diameterMM / 2 + lineWidthMM / 2
        case .line, .area: return (points.map { hypot($0.x, $0.y) }.max() ?? 0) + lineWidthMM / 2
        }
    }
}

extension Array where Element == PointElement {
    /// Symbol diameter (mm) at standard size.
    public var diameterMM: Double { 2 * (map(\.extentMM).max() ?? 0.3) }

    /// Drawing order: lowest color priority first (bottommost).
    public var drawingOrder: [PointElement] { sorted { $0.priority > $1.priority } }
}

/// Draws point symbols into a CGContext. `toCanvas` converts a paper offset (mm, y up) to a canvas point;
/// `mmToUnits` = canvas units per paper mm (for line widths and diameters).
public enum PointSymbolRenderer {
    public static func draw(_ elements: [PointElement], in ctx: CGContext, mmToUnits k: Double,
                            toCanvas: (Point2D) -> CGPoint) {
        // Point symbols are always drawn with solid strokes: the caller's dash pattern (e.g. from the footpath drawn
        // just before) would otherwise break the "x" of 115/313/419, the "V" of pits, rings and triangles into pieces.
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineDash(phase: 0, lengths: [])
        for e in elements.drawingOrder {
            guard let rgb = rgbComponents(hex: e.colorHex) else { continue }
            let color = CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            let c = toCanvas(Point2D(x: e.points.first?.x ?? 0, y: e.points.first?.y ?? 0))
            switch e.kind {
            case .dot:
                let r = e.diameterMM / 2 * k
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            case .circle:
                let r = e.diameterMM / 2 * k
                ctx.setStrokeColor(color)
                ctx.setLineWidth(max(e.lineWidthMM * k, 0.5))
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            case .line, .area:
                guard let first = e.points.first else { continue }
                ctx.beginPath()
                ctx.move(to: toCanvas(first))
                for p in e.points.dropFirst() { ctx.addLine(to: toCanvas(p)) }
                if e.kind == .area {
                    ctx.closePath()
                    ctx.setFillColor(color)
                    ctx.fillPath()
                } else {
                    ctx.setStrokeColor(color)
                    ctx.setLineWidth(max(e.lineWidthMM * k, 0.5))
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.strokePath()
                }
            }
        }
    }
}
