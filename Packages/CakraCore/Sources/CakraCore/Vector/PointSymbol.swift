import CoreGraphics
import Foundation

/// Satu elemen gambar simbol titik OCAD, dalam mm kertas relatif ke pusat simbol (x kanan, y atas).
public struct PointElement: Codable, Hashable, Sendable {
    public enum Kind: Int, Codable, Sendable {
        case line = 1, area = 2, circle = 3, dot = 4
    }

    public var kind: Kind
    public var colorHex: String
    /// Urutan warna di tabel warna OCAD; angka kecil = digambar paling atas.
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

    /// Jari-jari terluar elemen (mm), untuk ukuran simbol dan area pilih.
    public var extentMM: Double {
        switch kind {
        case .dot: return diameterMM / 2
        case .circle: return diameterMM / 2 + lineWidthMM / 2
        case .line, .area: return (points.map { hypot($0.x, $0.y) }.max() ?? 0) + lineWidthMM / 2
        }
    }
}

extension Array where Element == PointElement {
    /// Diameter simbol (mm) pada ukuran standar.
    public var diameterMM: Double { 2 * (map(\.extentMM).max() ?? 0.3) }

    /// Urutan gambar: prioritas warna terendah lebih dulu (paling bawah).
    public var drawingOrder: [PointElement] { sorted { $0.priority > $1.priority } }
}

/// Menggambar simbol titik ke CGContext. `toCanvas` mengubah offset kertas (mm, y atas) ke titik canvas;
/// `mmToUnits` = satuan canvas per mm kertas (untuk tebal garis dan diameter).
public enum PointSymbolRenderer {
    public static func draw(_ elements: [PointElement], in ctx: CGContext, mmToUnits k: Double,
                            toCanvas: (Point2D) -> CGPoint) {
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
