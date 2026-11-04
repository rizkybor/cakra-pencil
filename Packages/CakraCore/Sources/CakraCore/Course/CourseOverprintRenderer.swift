import CoreGraphics
import CoreText
import Foundation

/// Gambar overprint lintasan ke CGContext (raster export dan overlay MapKit).
public enum CourseOverprintRenderer {
    /// - Parameters:
    ///   - point: meter tanah (UTM) → koordinat konteks.
    ///   - unitsPerMeter: skala meter tanah → unit konteks (untuk tebal garis, jari-jari, tinggi huruf).
    ///   - flipped: konteks bersumbu y ke bawah (MapKit), agar teks tidak terbalik.
    ///   - minLineWidth: tebal minimum di unit konteks (agar tetap terlihat saat zoom jauh).
    public static func draw(_ o: CourseOverprint, in ctx: CGContext, unitsPerMeter: Double, flipped: Bool,
                            minLineWidth: Double = 0, alpha: Double = 1, point: (Point2D) -> CGPoint) {
        guard !o.isEmpty, let rgb = rgbComponents(hex: o.colorHex) else { return }
        let color = CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(max(o.lineWidthM * unitsPerMeter, minLineWidth))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineDash(phase: 0, lengths: [])
        for mark in o.marks {
            switch mark {
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
                drawText(text, at: point(center), capHeight: h * unitsPerMeter, color: color, flipped: flipped, in: ctx)
            }
        }
        ctx.restoreGState()
    }

    /// Teks berpusat; ukuran font diatur agar tinggi angka = `capHeight`.
    static func drawText(_ s: String, at c: CGPoint, capHeight: Double, color: CGColor, flipped: Bool, in ctx: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, capHeight / 0.72, nil)
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
