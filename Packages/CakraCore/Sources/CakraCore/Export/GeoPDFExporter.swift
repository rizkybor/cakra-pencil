import Foundation

/// PDF vektor seukuran kertas (A4 + margin) dengan georeferensi Geospatial PDF (ISO 32000-2 / ekstensi Adobe):
/// halaman membawa `/VP` → `/Measure /Subtype /GEO` dengan titik kontrol lat/lon di keempat pojok area peta dan
/// WKT CRS proyek. Terbaca di Avenza Maps, QGIS/GDAL, dan Adobe Acrobat (Geospatial location tool).
///
/// PDF ditulis manual (bukan lewat CGPDFContext) karena kamus `/VP` harus ada di objek halaman.
/// Isi: area (isi transparan), garis utara, sketsa, dan garis bezier sebagai path vektor; tebal sesuai mm.
public struct GeoPDFRequest: Sendable {
    public var title: String
    public var frame: MapFrame
    public var sheet: SheetSpec
    public var zone: UTMZone
    public var strokes: [Stroke]
    public var features: [Feature]
    public var grid: NorthGrid?

    public init(title: String, frame: MapFrame, sheet: SheetSpec, zone: UTMZone, strokes: [Stroke], features: [Feature], grid: NorthGrid? = nil) {
        self.title = title
        self.frame = frame
        self.sheet = sheet
        self.zone = zone
        self.strokes = strokes
        self.features = features
        self.grid = grid
    }
}

public enum GeoPDFExporter {
    static let ptPerMM = 72 / 25.4

    public static func export(_ req: GeoPDFRequest, to url: URL) throws {
        try document(req).write(to: url, options: .atomic)
    }

    /// Ukuran halaman penuh (pt) dan kotak area peta di dalamnya (pt, origin kiri bawah).
    public static func layout(_ sheet: SheetSpec) -> (page: (w: Double, h: Double), map: (x0: Double, y0: Double, x1: Double, y1: Double)) {
        let m = sheet.marginMM * ptPerMM
        let w = (sheet.mappingWidthMM + 2 * sheet.marginMM) * ptPerMM
        let h = (sheet.mappingHeightMM + 2 * sheet.marginMM) * ptPerMM
        return ((w, h), (m, m, w - m, h - m))
    }

    public static func document(_ req: GeoPDFRequest) -> Data {
        let (page, box) = layout(req.sheet)
        let e = req.frame.extent
        let k = 1000 / Double(req.sheet.scaleDenominator) * ptPerMM  // meter tanah → pt
        func pt(_ p: Point2D) -> String { "\(n(box.x0 + (p.x - e.minX) * k)) \(n(box.y0 + (p.y - e.minY) * k))" }

        // MARK: Isi halaman
        var c = "q\n"
        // Potong ke area peta.
        c += "\(n(box.x0)) \(n(box.y0)) \(n(box.x1 - box.x0)) \(n(box.y1 - box.y0)) re W n\n"
        c += "1 J 1 j\n"
        let visible = req.features.filter { $0.isVisible && $0.nodes.count >= ($0.kind == .point ? 1 : 2) }
        func path(_ f: Feature) -> String {
            var s = "\(pt(f.nodes[0].point)) m\n"
            for seg in f.segments {
                s += seg.isCurve ? "\(pt(seg.c1)) \(pt(seg.c2)) \(pt(seg.p3)) c\n" : "\(pt(seg.p3)) l\n"
            }
            return s + (f.isClosed ? "h\n" : "")
        }
        func rgb(_ hex: String) -> String {
            let v = rgbComponents(hex: hex) ?? (0, 0, 0)
            return "\(n(v.r)) \(n(v.g)) \(n(v.b))"
        }
        for f in visible where f.kind == .area {
            c += "q /GSArea gs \(rgb(f.colorHex)) rg\n\(path(f))f\nQ\n"
            c += "\(rgb(f.colorHex)) RG \(n(f.widthMM * ptPerMM)) w\n\(path(f))S\n"
        }
        if let g = req.grid, g.isEnabled, g.includeInExport {
            c += "q /GSGrid gs \(rgb(g.colorHex)) RG \(n(g.lineWidthMM * ptPerMM)) w\n"
            for (a, b) in g.lines(in: req.frame) { c += "\(pt(a)) m \(pt(b)) l S\n" }
            c += "Q\n"
        }
        for s in req.strokes {
            guard let first = s.points.first else { continue }
            let w = s.widthMM * ptPerMM
            if s.points.count == 1 {
                c += "\(rgb(s.colorHex)) RG \(n(w)) w \(pt(first)) m \(pt(first)) l S\n"
                continue
            }
            c += "\(rgb(s.colorHex)) RG \(n(w)) w \(pt(first)) m\n"
            for p in s.points.dropFirst() { c += "\(pt(p)) l\n" }
            c += "S\n"
        }
        for f in visible where f.kind == .line {
            c += "\(rgb(f.colorHex)) RG \(n(f.widthMM * ptPerMM)) w\n\(path(f))S\n"
        }
        // Simbol titik: elemen standar × sizeFactor, mm kertas → pt.
        for f in visible where f.kind == .point {
            guard let node = f.nodes.first else { continue }
            let center = node.point
            func at(_ mm: Point2D) -> String {
                let x = box.x0 + (center.x - e.minX) * k + mm.x * ptPerMM
                let y = box.y0 + (center.y - e.minY) * k + mm.y * ptPerMM
                return "\(n(x)) \(n(y))"
            }
            for el in f.scaledPointElements.drawingOrder {
                let o = el.points.first ?? Point2D(x: 0, y: 0)
                switch el.kind {
                case .dot:
                    c += "\(rgb(el.colorHex)) rg\n\(circlePath(center: o, r: el.diameterMM / 2, at))f\n"
                case .circle:
                    c += "\(rgb(el.colorHex)) RG \(n(el.lineWidthMM * ptPerMM)) w\n\(circlePath(center: o, r: el.diameterMM / 2, at))S\n"
                case .line, .area:
                    guard let first = el.points.first else { continue }
                    var s = "\(at(first)) m\n"
                    for q in el.points.dropFirst() { s += "\(at(q)) l\n" }
                    c += el.kind == .area ? "\(rgb(el.colorHex)) rg\n\(s)h f\n" : "\(rgb(el.colorHex)) RG \(n(el.lineWidthMM * ptPerMM)) w\n\(s)S\n"
                }
            }
        }
        c += "Q\n"
        // Batas area peta + keterangan di margin bawah (bila ada margin).
        c += "0.6 0.6 0.6 RG 0.3 w \(n(box.x0)) \(n(box.y0)) \(n(box.x1 - box.x0)) \(n(box.y1 - box.y0)) re S\n"
        if req.sheet.marginMM >= 4 {
            let caption = "\(req.title) · 1:\(req.sheet.scaleDenominator) · \(req.zone.label) (EPSG:\(req.zone.epsg)) · Cakra Pencil"
            c += "BT /F1 6 Tf 0.35 0.35 0.35 rg \(n(box.x0)) \(n(box.y0 - 8)) Td (\(pdfString(caption))) Tj ET\n"
        }

        // MARK: Georeferensi
        // LPTS = pojok kotak viewport dalam koordinat ternormalisasi; GPTS = lat lon pojok yang sama.
        let lpts: [(Double, Double)] = [(0, 0), (0, 1), (1, 1), (1, 0)]
        let corners = [Point2D(x: e.minX, y: e.minY), Point2D(x: e.minX, y: e.maxY), Point2D(x: e.maxX, y: e.maxY), Point2D(x: e.maxX, y: e.minY)]
        let gpts = corners.map { req.zone.unproject($0) }.map { "\(n($0.lat, 9)) \(n($0.lon, 9))" }.joined(separator: " ")
        let lptsString = lpts.map { "\(n($0.0)) \(n($0.1))" }.joined(separator: " ")

        // MARK: Objek PDF
        let content = Data(c.utf8)
        var objects: [Data] = []
        func add(_ s: String) -> Int { objects.append(Data(s.utf8)); return objects.count }
        let catalog = add("") // diisi setelah pages diketahui
        let pages = add("")
        let gcs = add("<< /Type /PROJCS /EPSG \(req.zone.epsg) /WKT (\(pdfString(req.zone.prjWKT))) >>")
        let measure = add("<< /Type /Measure /Subtype /GEO /Bounds [0 0 0 1 1 1 1 0] /GPTS [\(gpts)] /LPTS [\(lptsString)] /GCS \(gcs) 0 R /PDU [/M /SQM /DEG] >>")
        let font = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        let stream = objects.count + 1
        objects.append(Data("<< /Length \(content.count) >>\nstream\n".utf8) + content + Data("\nendstream".utf8))
        let gridOpacity = n(req.grid?.opacity ?? 1)
        let pageObj = add("""
        << /Type /Page /Parent \(pages) 0 R /MediaBox [0 0 \(n(page.w)) \(n(page.h))] /Contents \(stream) 0 R \
        /Resources << /Font << /F1 \(font) 0 R >> /ExtGState << /GSArea << /Type /ExtGState /ca 0.35 >> /GSGrid << /Type /ExtGState /CA \(gridOpacity) >> >> >> \
        /VP [<< /Type /Viewport /BBox [\(n(box.x0)) \(n(box.y0)) \(n(box.x1)) \(n(box.y1))] /Name (\(pdfString(req.title))) /Measure \(measure) 0 R >>] >>
        """)
        objects[catalog - 1] = Data("<< /Type /Catalog /Pages \(pages) 0 R >>".utf8)
        objects[pages - 1] = Data("<< /Type /Pages /Kids [\(pageObj) 0 R] /Count 1 >>".utf8)
        let info = add("<< /Title (\(pdfString(req.title))) /Producer (Cakra Pencil) /Creator (Cakra Pencil) >>")

        var out = Data("%PDF-1.7\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(out.count)
            out.append(Data("\(i + 1) 0 obj\n".utf8))
            out.append(body)
            out.append(Data("\nendobj\n".utf8))
        }
        let xref = out.count
        var trailer = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { trailer += String(format: "%010d 00000 n \n", o) }
        trailer += "trailer\n<< /Size \(objects.count + 1) /Root \(catalog) 0 R /Info \(info) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        out.append(Data(trailer.utf8))
        return out
    }

    /// Lingkaran sebagai 4 kurva kubik (kappa), koordinat mm relatif pusat simbol.
    static func circlePath(center o: Point2D, r: Double, _ at: (Point2D) -> String) -> String {
        let k = Feature.ellipseKappa * r
        func p(_ x: Double, _ y: Double) -> String { at(Point2D(x: o.x + x, y: o.y + y)) }
        return "\(p(r, 0)) m\n\(p(r, k)) \(p(k, r)) \(p(0, r)) c\n\(p(-k, r)) \(p(-r, k)) \(p(-r, 0)) c\n"
            + "\(p(-r, -k)) \(p(-k, -r)) \(p(0, -r)) c\n\(p(k, -r)) \(p(r, -k)) \(p(r, 0)) c\nh\n"
    }

    static func n(_ v: Double, _ decimals: Int = 3) -> String {
        var s = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    /// String literal PDF: escape \ ( ) dan ganti karakter non-Latin-1 (font standar memakai WinAnsi).
    static func pdfString(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "(": out += "\\("
            case ")": out += "\\)"
            case "·": out += "\\267"
            default: out += u.value < 128 ? String(u) : "?"
            }
        }
        return out
    }
}
