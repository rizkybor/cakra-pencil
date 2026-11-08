import CoreGraphics
import CoreText
import Foundation

/// Draws the course overprint into a CGContext (raster export and MapKit overlay).
public enum CourseOverprintRenderer {
    /// - Parameters:
    ///   - point: ground meters (UTM) → context coordinates.
    ///   - unitsPerMeter: scale from ground meters → context units (for line width, radius, letter height).
    ///   - flipped: context y axis points down (MapKit), so text is not upside down.
    ///   - minLineWidth: minimum width in context units (so it stays visible when zoomed far out).
    ///   - images: course object images by file name (missing ones are skipped).
    public static func draw(_ o: CourseOverprint, in ctx: CGContext, unitsPerMeter: Double, flipped: Bool,
                            minLineWidth: Double = 0, alpha: Double = 1, images: [String: CGImage] = [:],
                            point: (Point2D) -> CGPoint) {
        guard !o.isEmpty, let base = rgbComponents(hex: o.colorHex) else { return }
        var rgb = base
        var color = CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
        ctx.saveGState()
        // Course symbols must not mask black, brown or blue map detail (ISOM §3.7, ISSprOM §4.7):
        // multiply like printed overprint purple, so the map shows through.
        ctx.setBlendMode(.multiply)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(max(o.lineWidthM * unitsPerMeter, minLineWidth))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineDash(phase: 0, lengths: [])
        var fontName = "Helvetica"
        for mark in o.marks {
            switch mark {
            case let .font(bold, italic):
                fontName = "Helvetica" + (bold || italic ? "-" : "") + (bold ? "Bold" : "") + (italic ? "Oblique" : "")
            case let .color(hex):
                rgb = hex.flatMap { rgbComponents(hex: $0) } ?? base
                color = CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
                ctx.setStrokeColor(color)
                ctx.setFillColor(color)
            case let .width(w):
                ctx.setLineWidth(max((w ?? o.lineWidthM) * unitsPerMeter, minLineWidth))
            case let .circle(center, r):
                let c = point(center), rr = r * unitsPerMeter
                ctx.strokeEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
            case let .polyline(pts, closed):
                guard let first = pts.first else { continue }
                ctx.move(to: point(first))
                for p in pts.dropFirst() { ctx.addLine(to: point(p)) }
                if closed { ctx.closePath() }
                ctx.strokePath()
            case let .text(text, center, h):
                drawText(text, at: point(center), capHeight: h * unitsPerMeter, color: color, flipped: flipped, font: fontName, in: ctx)
            case let .fill(pts, opacity):
                guard let first = pts.first else { continue }
                ctx.saveGState()
                ctx.setFillColor(CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha * opacity))
                ctx.move(to: point(first))
                for p in pts.dropFirst() { ctx.addLine(to: point(p)) }
                ctx.closePath()
                ctx.fillPath()
                ctx.restoreGState()
            case let .image(name, center, w, h):
                guard let img = images[name] else { continue }
                let c = point(center), pw = w * unitsPerMeter, ph = h * unitsPerMeter
                ctx.saveGState()
                ctx.setBlendMode(.normal)   // photos / logos keep their own colors
                if flipped {
                    // Context y points down: flip so the image is not upside down.
                    ctx.translateBy(x: c.x - pw / 2, y: c.y + ph / 2)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.draw(img, in: CGRect(x: 0, y: 0, width: pw, height: ph))
                } else {
                    ctx.draw(img, in: CGRect(x: c.x - pw / 2, y: c.y - ph / 2, width: pw, height: ph))
                }
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }

    /// Centered text; font size is set so digit height = `capHeight`.
    static func drawText(_ s: String, at c: CGPoint, capHeight: Double, color: CGColor, flipped: Bool,
                         font name: String = "Helvetica", in ctx: CGContext) {
        let font = CTFontCreateWithName(name as CFString, capHeight / 0.72, nil)
        let attrs = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        guard let str = CFAttributedStringCreate(nil, s as CFString, attrs) else { return }
        let line = CTLineCreateWithAttributedString(str)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        if flipped { ctx.scaleBy(x: 1, y: -1) }
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: -width / 2, y: -capHeight / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
