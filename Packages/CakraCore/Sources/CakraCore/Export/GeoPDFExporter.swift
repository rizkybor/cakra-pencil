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
    /// Interval kontur (informasi; tidak digambar sejak kotak judul dihapus).
    public var contourIntervalM: Double?
    /// Isi file gambar objek lintasan (JPG/PNG) menurut nama file.
    public var images: [String: Data]

    public init(title: String, frame: MapFrame, sheet: SheetSpec, zone: UTMZone, strokes: [Stroke], features: [Feature], grid: NorthGrid? = nil,
                overprint: CourseOverprint? = nil, descriptions: DescriptionSheet? = nil,
                printLayout: CoursePrintLayout? = nil, contourIntervalM: Double? = nil, images: [String: Data] = [:]) {
        self.images = images
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
        // Gambar objek lintasan → XObject /Im0, /Im1, …; isian transparan → ExtGState per opacity.
        var imageNames: [String: String] = [:]
        var opacities: [Double] = []
        if let o = req.overprint {
            for m in o.marks {
                if case let .image(name, _, _, _) = m, imageNames[name] == nil, req.images[name] != nil {
                    imageNames[name] = "Im\(imageNames.count)"
                }
                if case let .fill(_, op) = m, !opacities.contains(op) { opacities.append(op) }
            }
        }
        if let o = req.overprint, !o.isEmpty {
            c += overprintContent(o, pt: pt, k: k, rgb: rgb, images: imageNames, opacities: opacities)
        }
        c += "Q\n"
        // Peta lomba: deskripsi kontrol di atas peta (di dalam area peta).
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
        func addStream(_ dict: String, _ body: Data) -> Int {
            objects.append(Data("<< \(dict) /Length \(body.count) >>\nstream\n".utf8) + body + Data("\nendstream".utf8))
            return objects.count
        }
        var xobjects: [String] = []
        for (file, name) in imageNames.sorted(by: { $0.value < $1.value }) {
            guard let data = req.images[file], let img = CourseImages.pdfImage(data) else { continue }
            var dict = img.dictionary
            if let m = img.mask { dict += " /SMask \(addStream(m.dictionary, m.stream)) 0 R" }
            xobjects.append("/\(name) \(addStream(dict, img.stream)) 0 R")
        }
        let stream = objects.count + 1
        objects.append(Data("<< /Length \(content.count) >>\nstream\n".utf8) + content + Data("\nendstream".utf8))
        var extraPages: [Int] = []
        let gridOpacity = n(req.grid?.opacity ?? 1)
        let pageObj = add("""
        << /Type /Page /Parent \(pages) 0 R /MediaBox [0 0 \(n(page.w)) \(n(page.h))] /Contents \(stream) 0 R \
        /Resources << /Font << /F1 \(font) 0 R /F2 \(bold) 0 R >> /XObject << \(xobjects.joined(separator: " ")) >> \
        /ExtGState << /GSArea << /Type /ExtGState /ca 0.35 >> /GSGrid << /Type /ExtGState /CA \(gridOpacity) >> \
        \(opacities.enumerated().map { "/GSFill\($0.offset) << /Type /ExtGState /ca \(n($0.element)) >>" }.joined(separator: " ")) >> >> \
        /VP [<< /Type /Viewport /BBox [\(n(box.x0)) \(n(box.y0)) \(n(box.x1)) \(n(box.y1))] /Name (\(pdfString(req.title))) /Measure \(measure) 0 R >>] >>
        """)
        objects[catalog - 1] = Data("<< /Type /Catalog /Pages \(pages) 0 R >>".utf8)
        let separatePage = req.printLayout.map { $0.separateDescriptionPage || !$0.descriptionOnMap } ?? true
        if let sheet = req.descriptions, separatePage {
            let body = Data(descriptionContent(sheet, maxRows: req.printLayout?.descriptionMaxRows, symbols: req.printLayout?.descriptionSymbols ?? true,
                                                  color: req.printLayout?.descriptionColor ?? .black).utf8)
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
    static func overprintContent(_ o: CourseOverprint, pt: (Point2D) -> String, k: Double, rgb: (String) -> String,
                                 images: [String: String] = [:], opacities: [Double] = []) -> String {
        var c = "q 1 J 1 j [] 0 d \(rgb(o.colorHex)) RG \(rgb(o.colorHex)) rg \(n(o.lineWidthM * k)) w\n"
        func xy(_ p: Point2D) -> (Double, Double)? {
            let v = pt(p).split(separator: " ").compactMap { Double($0) }
            return v.count == 2 ? (v[0], v[1]) : nil
        }
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
            case let .fill(pts, op):
                guard let first = pts.first, let gs = opacities.firstIndex(of: op) else { continue }
                c += "q /GSFill\(gs) gs \(pt(first)) m\n" + pts.dropFirst().map { "\(pt($0)) l\n" }.joined() + "h f Q\n"
            case let .image(name, center, w, h):
                guard let res = images[name], let p = xy(center) else { continue }
                let pw = w * k, ph = h * k
                c += "q \(n(pw)) 0 0 \(n(ph)) \(n(p.0 - pw / 2)) \(n(p.1 - ph / 2)) cm /\(res) Do Q\n"
            }
        }
        return c + "Q\n"
    }

    /// Halaman A4 berisi tabel deskripsi (kotak 7 mm) di kiri atas.
    static func descriptionContent(_ d: DescriptionSheet, maxRows: Int? = nil, symbols: Bool = true,
                                   color: CoursePrintLayout.DescriptionColor = .black) -> String {
        let cell = 7 * ptPerMM
        var c = "", height = 0.0
        for (i, col) in d.columns(maxRows: maxRows).enumerated() {
            let (table, h) = descriptionTable(col, x0: 40 + Double(i) * cell * 8, yTop: 800, cell: cell, background: false, symbols: symbols, color: color)
            c += table
            height = max(height, h)
        }
        return c + "BT /F1 6 Tf 40 \(n(800 - height - 14)) Td (\(pdfString("Cakra Pencil · deskripsi kontrol IOF \(symbols ? "2018" : "(teks)")"))) Tj ET\n"
    }

    /// Tinggi tabel deskripsi (pt) untuk ukuran kotak `cell`.
    static func descriptionTableHeight(_ d: DescriptionSheet, cell: Double) -> Double {
        Double(d.rows.count + (d.isContinuation ? 0 : 1 + (d.title.isEmpty ? 0 : 1) + (d.organizer.isEmpty ? 0 : 1))) * cell
    }

    /// Jarak blok deskripsi dari tepi area peta saat di pojok (mm).
    public static let descriptionInsetMM = 4.0

    /// Ukuran blok deskripsi di kertas (mm): kolom berdampingan, tinggi = kolom tertinggi.
    public static func descriptionBlockSizeMM(_ d: DescriptionSheet, layout: CoursePrintLayout) -> (w: Double, h: Double) {
        let cell = clampedCellMM(layout)
        let cols = d.columns(maxRows: layout.descriptionMaxRows)
        return (Double(cols.count) * cell * 8, cols.map { descriptionTableHeight($0, cell: cell) }.max() ?? 0)
    }

    /// Pojok kiri atas blok deskripsi dari pojok kiri atas area peta (mm), di dalam area peta.
    public static func descriptionOriginMM(block: (w: Double, h: Double), layout: CoursePrintLayout, sheet: SheetSpec) -> Point2D {
        let mw = sheet.mappingWidthMM, mh = sheet.mappingHeightMM, inset = descriptionInsetMM
        var o: Point2D
        if let off = layout.descriptionOffsetMM {
            o = off
        } else {
            let c = layout.descriptionCorner
            o = Point2D(x: c.isLeft ? inset : mw - inset - block.w, y: c.isTop ? inset : mh - inset - block.h)
        }
        o.x = min(max(o.x, 0), max(mw - block.w, 0))
        o.y = min(max(o.y, 0), max(mh - block.h, 0))
        return o
    }

    static func clampedCellMM(_ layout: CoursePrintLayout) -> Double {
        min(max(layout.descriptionCellMM, CoursePrintLayout.cellRangeMM.lowerBound), CoursePrintLayout.cellRangeMM.upperBound)
    }

    /// Tabel deskripsi: kolom A (nomor), B (kode), lalu C–H bergambar IOF (`symbols`) atau deskripsi teks selebar
    /// 6 kotak; garis tebal tiap 3 kontrol. `background`: isi putih (untuk ditempel di atas peta).
    static func descriptionTable(_ d: DescriptionSheet, x0: Double, yTop: Double, cell: Double, background: Bool,
                                 symbols: Bool = true, color: CoursePrintLayout.DescriptionColor = .black) -> (String, Double) {
        let s = cell / (7 * ptPerMM)  // ukuran huruf mengikuti ukuran kotak
        let width = cell * 8
        let height = descriptionTableHeight(d, cell: cell)
        var y = yTop
        var c = "q\n"
        if background { c += "1 1 1 rg \(n(x0)) \(n(yTop - height)) \(n(width)) \(n(height)) re f\n" }
        let ink = rgbComponents(hex: color.hex) ?? (0, 0, 0)
        let inkRGB = "\(n(ink.0)) \(n(ink.1)) \(n(ink.2))"
        c += "\(inkRGB) RG \(inkRGB) rg \(n(0.5 * s)) w\n"
        func text(_ str: String, x: Double, y: Double, size: Double, center: Bool = false, maxWidth: Double = 0, font: String = "F1") {
            let w = textWidth(str, size: size, bold: font == "F2")
            let tx = center ? x + (maxWidth - w) / 2 : x
            c += "BT /\(font) \(n(size)) Tf \(n(tx)) \(n(y)) Td (\(pdfString(str))) Tj ET\n"
        }
        func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { c += "\(n(x)) \(n(y)) \(n(w)) \(n(h)) re S\n" }

        if !d.isContinuation, !d.title.isEmpty {
            y -= cell
            box(x0, y, width, cell)
            text(fit(d.title, width: width - 4, size: 9 * s, bold: true), x: x0, y: y + cell * 0.32, size: 9 * s, center: true, maxWidth: width, font: "F2")
        }
        if !d.isContinuation, !d.organizer.isEmpty {
            y -= cell
            box(x0, y, width, cell)
            text(fit(d.organizer, width: width - 4, size: 7.5 * s), x: x0, y: y + cell * 0.34, size: 7.5 * s, center: true, maxWidth: width)
        }
        if !d.isContinuation {
            y -= cell
            box(x0, y, cell * 4, cell); box(x0 + cell * 4, y, cell * 2, cell); box(x0 + cell * 6, y, cell * 2, cell)
            text(fit(d.courseName, width: cell * 4 - 4, size: 9 * s, bold: true), x: x0 + 3 * s, y: y + cell * 0.32, size: 9 * s, font: "F2")
            text(d.lengthText, x: x0 + cell * 4, y: y + cell * 0.32, size: 8 * s, center: true, maxWidth: cell * 2)
            text(d.climbText, x: x0 + cell * 6, y: y + cell * 0.32, size: 8 * s, center: true, maxWidth: cell * 2)
        }

        var controlRows = 0
        for row in d.rows {
            y -= cell
            if symbols, row.kind == .finish {
                c += finishRow(row, x0: x0, y: y, cell: cell, s: s)
                continue
            }
            box(x0, y, cell, cell); box(x0 + cell, y, cell, cell)
            if symbols {
                // C–H: satu kotak per kolom; garis tebal setelah C dan F seperti lembar IOF.
                for k in 2..<8 { box(x0 + cell * Double(k), y, cell, cell) }
                c += "\(n(1.2 * s)) w \(n(x0 + cell * 3)) \(n(y)) m \(n(x0 + cell * 3)) \(n(y + cell)) l S "
                    + "\(n(x0 + cell * 6)) \(n(y)) m \(n(x0 + cell * 6)) \(n(y + cell)) l S \(n(0.5 * s)) w\n"
            } else {
                box(x0 + cell * 2, y, cell * 6, cell)
            }
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
            if symbols {
                let desc = row.description
                let cols: [[IOFPictogram.Shape]?] = [IOFPictogram.shapes(desc.which), IOFPictogram.shapes(desc.feature),
                                                     IOFPictogram.shapes(desc.appearance), IOFPictogram.dimensionShapes(desc.dimension),
                                                     IOFPictogram.shapes(desc.location), IOFPictogram.shapes(desc.other)]
                let pad = cell * 0.1
                for (k, shapes) in cols.enumerated() {
                    guard let shapes else { continue }
                    c += IOFPictogram.pdf(shapes, x0: x0 + cell * Double(k + 2) + pad, y0: y + pad, size: cell - 2 * pad,
                                          textWidth: { textWidth($0, size: $1) })
                }
                // Kolom yang tidak diisi dibiarkan kosong.
                if row.kind == .control, controlRows % 3 == 0 {
                    c += "\(n(1.5 * s)) w \(n(x0)) \(n(y)) m \(n(x0 + width)) \(n(y)) l S \(n(0.5 * s)) w\n"
                }
                continue
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

    /// Baris finish IOF (simbol 14.3): lingkaran kontrol terakhir, garis putus-putus dengan jarak, lalu
    /// lingkaran finish ganda, selebar 8 kotak.
    static func finishRow(_ row: DescriptionSheet.Row, x0: Double, y: Double, cell: Double, s: Double) -> String {
        let width = cell * 8, cy = y + cell / 2
        var c = "\(n(x0)) \(n(y)) \(n(width)) \(n(cell)) re S\n"
        let r = cell * 0.26
        let left = x0 + cell * 0.55, right = x0 + width - cell * 0.55
        c += circlePath(center: Point2D(x: 0, y: 0), r: r, { "\(n(left + $0.x)) \(n(cy + $0.y))" }) + "S\n"
        c += circlePath(center: Point2D(x: 0, y: 0), r: r, { "\(n(right + $0.x)) \(n(cy + $0.y))" }) + "S\n"
        c += circlePath(center: Point2D(x: 0, y: 0), r: r * 0.62, { "\(n(right + $0.x)) \(n(cy + $0.y))" }) + "S\n"
        let label = row.finishMeters.map { "\($0) m" } ?? ""
        let size = 7.5 * s
        let tw = textWidth(label, size: size)
        let gap = label.isEmpty ? 0 : tw / 2 + cell * 0.25
        let mid = x0 + width / 2
        c += "[\(n(cell * 0.35)) \(n(cell * 0.2))] 0 d "
        c += "\(n(left + r)) \(n(cy)) m \(n(mid - gap)) \(n(cy)) l S \(n(mid + gap)) \(n(cy)) m \(n(right - r - cell * 0.12)) \(n(cy)) l S [] 0 d\n"
        // Mata panah masuk ke lingkaran finish.
        let tip = right - r
        c += "\(n(tip - cell * 0.22)) \(n(cy + cell * 0.16)) m \(n(tip)) \(n(cy)) l \(n(tip - cell * 0.22)) \(n(cy - cell * 0.16)) l S\n"
        if !label.isEmpty { c += "BT /F1 \(n(size)) Tf \(n(mid - tw / 2)) \(n(cy - size * 0.35)) Td (\(pdfString(label))) Tj ET\n" }
        return c
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

    /// Deskripsi kontrol di atas peta (latar putih): di pojok pilihan atau posisi bebas, dibagi ke beberapa
    /// kolom berdampingan bila baris melebihi batas per kolom.
    static func decorations(_ layout: CoursePrintLayout, sheet d: DescriptionSheet, req: GeoPDFRequest,
                            box: (x0: Double, y0: Double, x1: Double, y1: Double)) -> String {
        guard layout.descriptionOnMap else { return "" }
        let cellMM = clampedCellMM(layout)
        let block = descriptionBlockSizeMM(d, layout: layout)
        let o = descriptionOriginMM(block: block, layout: layout, sheet: req.sheet)
        var c = ""
        for (i, col) in d.columns(maxRows: layout.descriptionMaxRows).enumerated() {
            let x = box.x0 + (o.x + Double(i) * cellMM * 8) * ptPerMM
            c += descriptionTable(col, x0: x, yTop: box.y1 - o.y * ptPerMM, cell: cellMM * ptPerMM, background: true,
                                  symbols: layout.descriptionSymbols, color: layout.descriptionColor).0
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
            case "×": out += "\\327"
            default: out += u.value < 128 ? String(u) : "?"
            }
        }
        return out
    }
}
