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
    /// Overprint lintasan (ungu) di atas peta.
    public var overprint: CourseOverprint?
    /// Lembar deskripsi kontrol (di peta menurut `printLayout`, dan/atau halaman kedua).
    public var descriptions: DescriptionSheet?
    /// Tata letak peta lomba satu halaman; nil = deskripsi di halaman kedua (format lama).
    public var printLayout: CoursePrintLayout?
    /// Interval kontur untuk kotak judul (nil = tidak ditulis).
    public var contourIntervalM: Double?

    public init(title: String, frame: MapFrame, sheet: SheetSpec, zone: UTMZone, strokes: [Stroke], features: [Feature], grid: NorthGrid? = nil,
                overprint: CourseOverprint? = nil, descriptions: DescriptionSheet? = nil,
                printLayout: CoursePrintLayout? = nil, contourIntervalM: Double? = nil) {
        self.overprint = overprint
        self.descriptions = descriptions
        self.printLayout = printLayout
        self.contourIntervalM = contourIntervalM
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
            if f.isSymbolArea {
                // Seperti OCAD/OOM: isi warna penuh, tanpa tepi.
                c += "\(rgb(f.colorHex)) rg\n\(path(f))f\n"
            } else {
                c += "q /GSArea gs \(rgb(f.colorHex)) rg\n\(path(f))f\nQ\n"
                c += "\(rgb(f.colorHex)) RG \(n(f.widthMM * ptPerMM)) w\n\(path(f))S\n"
            }
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
            // Ujung: 0 J / 0 j = rata + tajam, 1 J / 1 j = bulat. Pola: [garis jeda] 0 d.
            let caps = f.roundCaps == false ? "0 J 0 j" : "1 J 1 j"
            let dash = f.effectiveDashMM.map { "[\($0.map { n($0 * ptPerMM) }.joined(separator: " "))] 0 d" } ?? "[] 0 d"
            if let casing = f.casingColorHex, let inner = f.innerWidthMM {
                c += "\(caps) \(dash) \(rgb(casing)) RG \(n(f.widthMM * ptPerMM)) w\n\(path(f))S\n"
                c += "[] 0 d \(rgb(f.colorHex)) RG \(n(inner * ptPerMM)) w\n\(path(f))S\n"
            } else {
                c += "\(caps) \(dash) \(rgb(f.colorHex)) RG \(n(f.widthMM * ptPerMM)) w\n\(path(f))S\n"
            }
        }
        c += "1 J 1 j [] 0 d\n"
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
        if let o = req.overprint, !o.isEmpty {
            c += overprintContent(o, pt: pt, k: k, rgb: rgb)
        }
        c += "Q\n"
        // Peta lomba: deskripsi, panah utara, dan kotak judul di atas peta (di dalam area peta).
        if let layout = req.printLayout, let d = req.descriptions {
            c += decorations(layout, sheet: d, req: req, box: box)
        }
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
        let bold = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
        let stream = objects.count + 1
        objects.append(Data("<< /Length \(content.count) >>\nstream\n".utf8) + content + Data("\nendstream".utf8))
        var extraPages: [Int] = []
        let gridOpacity = n(req.grid?.opacity ?? 1)
        let pageObj = add("""
        << /Type /Page /Parent \(pages) 0 R /MediaBox [0 0 \(n(page.w)) \(n(page.h))] /Contents \(stream) 0 R \
        /Resources << /Font << /F1 \(font) 0 R /F2 \(bold) 0 R >> /ExtGState << /GSArea << /Type /ExtGState /ca 0.35 >> /GSGrid << /Type /ExtGState /CA \(gridOpacity) >> >> >> \
        /VP [<< /Type /Viewport /BBox [\(n(box.x0)) \(n(box.y0)) \(n(box.x1)) \(n(box.y1))] /Name (\(pdfString(req.title))) /Measure \(measure) 0 R >>] >>
        """)
        objects[catalog - 1] = Data("<< /Type /Catalog /Pages \(pages) 0 R >>".utf8)
        let separatePage = req.printLayout.map { $0.separateDescriptionPage || !$0.descriptionOnMap } ?? true
        if let sheet = req.descriptions, separatePage {
            let body = Data(descriptionContent(sheet).utf8)
            let streamObj = objects.count + 1
            objects.append(Data("<< /Length \(body.count) >>\nstream\n".utf8) + body + Data("\nendstream".utf8))
            extraPages.append(add("<< /Type /Page /Parent \(pages) 0 R /MediaBox [0 0 595.276 841.89] /Contents \(streamObj) 0 R /Resources << /Font << /F1 \(font) 0 R /F2 \(bold) 0 R >> >> >>"))
        }
        let kids = ([pageObj] + extraPages).map { "\($0) 0 R" }.joined(separator: " ")
        objects[pages - 1] = Data("<< /Type /Pages /Kids [\(kids)] /Count \(1 + extraPages.count) >>".utf8)
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

    // MARK: Lintasan

    /// Overprint ungu: lingkaran, segitiga start, leg, dan nomor (Helvetica, tinggi angka = tinggi nomor IOF).
    static func overprintContent(_ o: CourseOverprint, pt: (Point2D) -> String, k: Double, rgb: (String) -> String) -> String {
        var c = "q 1 J 1 j [] 0 d \(rgb(o.colorHex)) RG \(rgb(o.colorHex)) rg \(n(o.lineWidthM * k)) w\n"
        for mark in o.marks {
            switch mark {
            case let .circle(center, r):
                c += circlePath(center: center, r: r, pt) + "S\n"
            case let .polyline(pts, closed):
                guard let first = pts.first else { continue }
                c += "\(pt(first)) m\n" + pts.dropFirst().map { "\(pt($0)) l\n" }.joined() + (closed ? "h\n" : "") + "S\n"
            case let .text(text, center, h):
                // Tinggi angka Helvetica ±0,72 em; lebar angka 0,556 em.
                let size = h * k / 0.72
                let w = Double(text.count) * 0.556 * size
                let xy = pt(center).split(separator: " ").compactMap { Double($0) }
                guard xy.count == 2 else { continue }
                c += "BT /F1 \(n(size)) Tf \(n(xy[0] - w / 2)) \(n(xy[1] - h * k / 2)) Td (\(pdfString(text))) Tj ET\n"
            }
        }
        return c + "Q\n"
    }

    /// Halaman A4 berisi tabel deskripsi (kotak 7 mm) di kiri atas.
    static func descriptionContent(_ d: DescriptionSheet) -> String {
        let cell = 7 * ptPerMM
        let (table, height) = descriptionTable(d, x0: 40, yTop: 800, cell: cell, background: false)
        return table + "BT /F1 6 Tf 40 \(n(800 - height - 14)) Td (\(pdfString("Cakra Pencil · deskripsi kontrol IOF (teks)"))) Tj ET\n"
    }

    /// Tinggi tabel deskripsi (pt) untuk ukuran kotak `cell`.
    static func descriptionTableHeight(_ d: DescriptionSheet, cell: Double) -> Double {
        Double(d.rows.count + 1 + (d.title.isEmpty ? 0 : 1)) * cell
    }

    /// Tabel deskripsi: kolom A (nomor), B (kode), lalu deskripsi teks selebar 6 kotak; garis tebal tiap 3 kontrol.
    /// `background`: isi putih (untuk ditempel di atas peta).
    static func descriptionTable(_ d: DescriptionSheet, x0: Double, yTop: Double, cell: Double, background: Bool) -> (String, Double) {
        let s = cell / (7 * ptPerMM)  // ukuran huruf mengikuti ukuran kotak
        let width = cell * 8
        let height = descriptionTableHeight(d, cell: cell)
        var y = yTop
        var c = "q\n"
        if background { c += "1 1 1 rg \(n(x0)) \(n(yTop - height)) \(n(width)) \(n(height)) re f\n" }
        c += "0 0 0 RG 0 0 0 rg \(n(0.5 * s)) w\n"
        func text(_ str: String, x: Double, y: Double, size: Double, center: Bool = false, maxWidth: Double = 0, font: String = "F1") {
            let w = textWidth(str, size: size, bold: font == "F2")
            let tx = center ? x + (maxWidth - w) / 2 : x
            c += "BT /\(font) \(n(size)) Tf \(n(tx)) \(n(y)) Td (\(pdfString(str))) Tj ET\n"
        }
        func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { c += "\(n(x)) \(n(y)) \(n(w)) \(n(h)) re S\n" }

        if !d.title.isEmpty {
            y -= cell
            box(x0, y, width, cell)
            text(fit(d.title, width: width - 4, size: 9 * s, bold: true), x: x0, y: y + cell * 0.32, size: 9 * s, center: true, maxWidth: width, font: "F2")
        }
        y -= cell
        box(x0, y, cell * 4, cell); box(x0 + cell * 4, y, cell * 2, cell); box(x0 + cell * 6, y, cell * 2, cell)
        text(fit(d.courseName, width: cell * 4 - 4, size: 9 * s, bold: true), x: x0 + 3 * s, y: y + cell * 0.32, size: 9 * s, font: "F2")
        text(d.lengthText, x: x0 + cell * 4, y: y + cell * 0.32, size: 8 * s, center: true, maxWidth: cell * 2)
        text(d.climbText, x: x0 + cell * 6, y: y + cell * 0.32, size: 8 * s, center: true, maxWidth: cell * 2)

        var controlRows = 0
        for row in d.rows {
            y -= cell
            box(x0, y, cell, cell); box(x0 + cell, y, cell, cell); box(x0 + cell * 2, y, cell * 6, cell)
            let mid = (x: x0 + cell / 2, y: y + cell / 2)
            switch row.kind {
            case .start:
                let r = cell * 0.32
                let pts = (0..<3).map { i -> String in
                    let a = Double.pi / 2 + Double(i) * 2 * .pi / 3
                    return "\(n(mid.x + r * cos(a))) \(n(mid.y + r * sin(a)))"
                }
                c += "\(pts[0]) m \(pts[1]) l \(pts[2]) l h S\n"
            case .finish:
                c += circlePath(center: Point2D(x: 0, y: 0), r: cell * 0.22, { "\(n(mid.x + $0.x)) \(n(mid.y + $0.y))" }) + "S\n"
                c += circlePath(center: Point2D(x: 0, y: 0), r: cell * 0.34, { "\(n(mid.x + $0.x)) \(n(mid.y + $0.y))" }) + "S\n"
            case .control:
                controlRows += 1
                text(row.number, x: x0, y: y + cell * 0.3, size: 10 * s, center: true, maxWidth: cell, font: "F2")
                text(row.code, x: x0 + cell, y: y + cell * 0.3, size: 10 * s, center: true, maxWidth: cell)
            }
            // Deskripsi: 1–2 baris, huruf mengecil bila panjang.
            let lines = wrap(row.text, maxChars: 34)
            let small = wrap(row.text, maxChars: 42)
            if lines.count <= 1 {
                text(lines.first ?? "", x: x0 + cell * 2 + 3 * s, y: y + cell * 0.32, size: 7 * s)
            } else if small.count == 1 {
                text(small[0], x: x0 + cell * 2 + 3 * s, y: y + cell * 0.34, size: 5.8 * s)
            } else {
                text(small[0], x: x0 + cell * 2 + 3 * s, y: y + cell * 0.56, size: 5.8 * s)
                text(small.count > 2 ? small[1] + "..." : small[1], x: x0 + cell * 2 + 3 * s, y: y + cell * 0.14, size: 5.8 * s)
            }
            if row.kind == .control, controlRows % 3 == 0 { c += "\(n(1.5 * s)) w \(n(x0)) \(n(y)) m \(n(x0 + width)) \(n(y)) l S \(n(0.5 * s)) w\n" }
        }
        c += "\(n(1.5 * s)) w \(n(x0)) \(n(y)) \(n(width)) \(n(yTop - y)) re S\nQ\n"
        return (c, height)
    }

    /// Lebar teks Helvetica (perkiraan rata-rata lebar huruf).
    static func textWidth(_ s: String, size: Double, bold: Bool = false) -> Double {
        Double(s.count) * size * (bold ? 0.58 : 0.52)
    }

    /// Potong teks agar muat lebar (pt), dengan "...".
    static func fit(_ s: String, width: Double, size: Double, bold: Bool = false) -> String {
        guard textWidth(s, size: size, bold: bold) > width else { return s }
        var t = s
        while !t.isEmpty, textWidth(t + "...", size: size, bold: bold) > width { t.removeLast() }
        return t + "..."
    }

    /// Panjang skala batang (m) yang enak dibaca: 15–30 mm di kertas.
    public static func scaleBarMeters(scale: Int) -> Double {
        let options: [Double] = [10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000]
        let mm = { (m: Double) in m * 1000 / Double(scale) }
        return options.last { mm($0) <= 30 } ?? options[0]
    }

    // MARK: Peta lomba (satu halaman)

    /// Deskripsi di sudut peta, panah utara, dan kotak judul + skala batang — semua berlatar putih di atas peta.
    static func decorations(_ layout: CoursePrintLayout, sheet d: DescriptionSheet, req: GeoPDFRequest,
                            box: (x0: Double, y0: Double, x1: Double, y1: Double)) -> String {
        var c = ""
        let inset = 4 * ptPerMM
        let corner = layout.descriptionCorner
        func text(_ str: String, x: Double, y: Double, size: Double, bold: Bool = false, center: Bool = false, maxWidth: Double = 0) {
            let w = textWidth(str, size: size, bold: bold)
            let tx = center ? x + (maxWidth - w) / 2 : x
            c += "BT /\(bold ? "F2" : "F1") \(n(size)) Tf \(n(tx)) \(n(y)) Td (\(pdfString(str))) Tj ET\n"
        }

        // 1. Deskripsi kontrol di sudut pilihan.
        if layout.descriptionOnMap {
            let cell = min(max(layout.descriptionCellMM, CoursePrintLayout.cellRangeMM.lowerBound), CoursePrintLayout.cellRangeMM.upperBound) * ptPerMM
            let w = cell * 8, h = descriptionTableHeight(d, cell: cell)
            let x = corner.isLeft ? box.x0 + inset : box.x1 - inset - w
            let yTop = corner.isTop ? box.y1 - inset : box.y0 + inset + h
            c += descriptionTable(d, x0: x, yTop: yTop, cell: cell, background: true).0
        }

        // 2. Panah utara di sudut atas yang tidak dipakai deskripsi.
        if layout.showNorthArrow {
            let left = !(layout.descriptionOnMap && corner == .topLeft)
            let bw = 13 * ptPerMM, bh = 20 * ptPerMM
            let x = left ? box.x0 + inset : box.x1 - inset - bw
            let y = box.y1 - inset - bh
            let magnetic = req.grid.map { $0.isEnabled && $0.reference == .magnetic } ?? false
            let decl = magnetic ? (req.grid?.declinationDeg ?? 0) : 0
            c += "q 1 1 1 rg 0 0 0 RG 0.5 w \(n(x)) \(n(y)) \(n(bw)) \(n(bh)) re B Q\n"
            text("U", x: x, y: y + bh - 5.2 * ptPerMM, size: 11, bold: true, center: true, maxWidth: bw)
            // Panah (diputar sesuai deklinasi bila utara magnetik): kepala segitiga + batang.
            let cx = x + bw / 2, cy = y + bh * 0.42
            let a = -decl * .pi / 180
            c += "q \(n(cos(a), 5)) \(n(sin(a), 5)) \(n(-sin(a), 5)) \(n(cos(a), 5)) \(n(cx)) \(n(cy)) cm 0 0 0 rg 0 0 0 RG 1.2 w\n"
            let L = 5.5 * ptPerMM
            c += "0 \(n(L)) m \(n(-1.6 * ptPerMM)) \(n(L - 3 * ptPerMM)) l \(n(1.6 * ptPerMM)) \(n(L - 3 * ptPerMM)) l h f\n"
            c += "0 \(n(L - 3 * ptPerMM)) m 0 \(n(-L)) l S Q\n"
            text(magnetic ? "Utara magnetik" : "Utara grid", x: x, y: y + 1.6 * ptPerMM, size: 5, center: true, maxWidth: bw)
        }

        // 3. Kotak judul di bawah (menghindari deskripsi bila deskripsi di sudut bawah).
        if layout.showTitleBlock {
            let w = min(105 * ptPerMM, box.x1 - box.x0 - 2 * inset), h = 17 * ptPerMM
            var x = (box.x0 + box.x1 - w) / 2
            if layout.descriptionOnMap, !corner.isTop {
                x = corner.isLeft ? box.x1 - inset - w : box.x0 + inset
            }
            let y = box.y0 + inset
            let c1 = w * 0.38, c2 = w * 0.28, c3 = w - c1 - c2
            c += "q 1 1 1 rg 0 0 0 RG 0.8 w \(n(x)) \(n(y)) \(n(w)) \(n(h)) re B 0.4 w \(n(x + c1)) \(n(y)) m \(n(x + c1)) \(n(y + h)) l S \(n(x + c1 + c2)) \(n(y)) m \(n(x + c1 + c2)) \(n(y + h)) l S Q\n"
            c += "0 0 0 rg\n"
            let pad = 2.2 * ptPerMM
            let event = d.title.isEmpty ? req.title : d.title
            // Nama acara: 1 baris 9 pt, atau 2 baris 7,5 pt bila panjang.
            var subtitleY = y + h - 9.5 * ptPerMM
            if textWidth(event, size: 9, bold: true) <= c1 - 2 * pad {
                text(event, x: x + pad, y: y + h - 5.5 * ptPerMM, size: 9, bold: true)
            } else {
                let perLine = max(8, Int((c1 - 2 * pad) / (7.5 * 0.58)))
                let lines = wrap(event, maxChars: perLine)
                text(fit(lines[0], width: c1 - 2 * pad, size: 7.5, bold: true), x: x + pad, y: y + h - 4.8 * ptPerMM, size: 7.5, bold: true)
                if lines.count > 1 {
                    let rest = lines.dropFirst().joined(separator: " ")
                    text(fit(rest, width: c1 - 2 * pad, size: 7.5, bold: true), x: x + pad, y: y + h - 8 * ptPerMM, size: 7.5, bold: true)
                }
                subtitleY = y + h - 11.6 * ptPerMM
            }
            if !layout.subtitle.isEmpty {
                text(fit(layout.subtitle, width: c1 - 2 * pad, size: 7), x: x + pad, y: subtitleY, size: 7)
            }
            text("Cakra Pencil", x: x + pad, y: y + 1.8 * ptPerMM, size: 4.5)
            // Lintasan: nama besar + panjang/tanjakan.
            text(fit(d.courseName, width: c2 - 2 * pad, size: 17, bold: true), x: x + c1, y: y + h - 8.2 * ptPerMM, size: 17, bold: true, center: true, maxWidth: c2)
            let info = [d.lengthText, d.climbText].filter { !$0.isEmpty }.joined(separator: " · ")
            text(info, x: x + c1, y: y + 2.6 * ptPerMM, size: 7.5, center: true, maxWidth: c2)
            // Skala, interval kontur, skala batang.
            let x3 = x + c1 + c2 + pad
            text("Skala 1:\(req.sheet.scaleDenominator)", x: x3, y: y + h - 4.8 * ptPerMM, size: 8, bold: true)
            if let ci = req.contourIntervalM {
                text("Interval kontur \(Fmt.number(ci, decimals: ci.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) m", x: x3, y: y + h - 8.4 * ptPerMM, size: 6.5)
            }
            if layout.showScaleBar {
                let meters = scaleBarMeters(scale: req.sheet.scaleDenominator)
                let len = meters * 1000 / Double(req.sheet.scaleDenominator) * ptPerMM
                let bx = x3, by = y + 3.6 * ptPerMM, bh = 1.3 * ptPerMM
                c += "q 0 0 0 RG 0.4 w\n"
                for i in 0..<4 {
                    let sx = bx + len / 4 * Double(i)
                    c += (i % 2 == 0 ? "0 0 0 rg" : "1 1 1 rg") + " \(n(sx)) \(n(by)) \(n(len / 4)) \(n(bh)) re B\n"
                }
                c += "Q 0 0 0 rg\n"
                text("0", x: bx - 1, y: by - 2.4 * ptPerMM, size: 5)
                let label = meters >= 1000 ? "\(Fmt.number(meters / 1000, decimals: 0)) km" : "\(Int(meters)) m"
                text(label, x: bx + len - textWidth(label, size: 5) / 2, y: by - 2.4 * ptPerMM, size: 5)
            }
        }
        return c
    }

    static func wrap(_ s: String, maxChars: Int) -> [String] {
        var lines: [String] = [], line = ""
        for word in s.split(separator: " ") {
            if line.isEmpty { line = String(word) } else if line.count + 1 + word.count <= maxChars { line += " " + word } else {
                lines.append(line); line = String(word)
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    /// Lingkaran sebagai 4 kurva kubik (kappa), koordinat mm relatif pusat simbol.
    static func circlePath(center o: Point2D, r: Double, _ at: (Point2D) -> String) -> String {
        let k = Feature.ellipseKappa * r
        func p(_ x: Double, _ y: Double) -> String { at(Point2D(x: o.x + x, y: o.y + y)) }
        return "\(p(r, 0)) m\n\(p(r, k)) \(p(k, r)) \(p(0, r)) c\n\(p(-k, r)) \(p(-r, k)) \(p(-r, 0)) c\n"
            + "\(p(-r, -k)) \(p(-k, -r)) \(p(0, -r)) c\n\(p(k, -r)) \(p(r, -k)) \(p(r, 0)) c\nh\n"
    }

    /// Angka PDF: titik desimal, tanpa nol di belakang. Aritmetika integer, bukan `String(format:)`
    /// (PDF peta lomba berisi ratusan ribu angka; uji performa: 4 s → jauh lebih cepat).
    static func n(_ v: Double, _ decimals: Int = 3) -> String {
        guard v.isFinite else { return "0" }
        let d = min(max(decimals, 0), 9)
        let p = pow10[d]
        // Pembulatan ke genap seperti printf (0,5 → 0; 0,125 → 0,12).
        let scaled = (abs(v) * Double(p)).rounded(.toNearestOrEven)
        guard scaled < 9e15 else {
            var s = String(format: "%.\(d)f", locale: Locale(identifier: "en_US_POSIX"), v)
            if s.contains(".") {
                while s.hasSuffix("0") { s.removeLast() }
                if s.hasSuffix(".") { s.removeLast() }
            }
            return s
        }
        let i = Int64(scaled)
        var frac = i % p
        var digits = d
        while digits > 0, frac % 10 == 0 { frac /= 10; digits -= 1 }
        var s = v < 0 && i != 0 ? "-" : ""
        s += String(i / p)
        if digits > 0 {
            let f = String(frac)
            s += "." + String(repeating: "0", count: digits - f.count) + f
        }
        return s
    }

    private static let pow10: [Int64] = (0...9).map { Int64(pow(10.0, Double($0))) }

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
