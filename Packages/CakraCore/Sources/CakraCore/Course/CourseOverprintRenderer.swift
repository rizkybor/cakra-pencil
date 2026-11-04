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
    ///   - images: gambar objek lintasan menurut nama file (yang tidak ada dilewati).
    public static func draw(_ o: CourseOverprint, in ctx: CGContext, unitsPerMeter: Double, flipped: Bool,
                            minLineWidth: Double = 0, alpha: Double = 1, images: [String: CGImage] = [:],
                            point: (Point2D) -> CGPoint) {
        guard !o.isEmpty, let base = rgbComponents(hex: o.colorHex) else { return }
        var rgb = base
        var color = CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
        ctx.saveGState()
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
                if flipped {
                    // Konteks y ke bawah: balik agar gambar tidak terbalik.
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

    /// Teks berpusat; ukuran font diatur agar tinggi angka = `capHeight`.
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
