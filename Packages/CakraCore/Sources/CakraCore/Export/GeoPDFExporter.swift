import Foundation

/// Paper-sized vector PDF (A4 + margin) with Geospatial PDF georeferencing (ISO 32000-2 / Adobe extension):
/// the page carries `/VP` → `/Measure /Subtype /GEO` with lat/lon control points at the four corners of the map area and
/// the project CRS WKT. Readable in Avenza Maps, QGIS/GDAL, and Adobe Acrobat (Geospatial location tool).
///
/// The PDF is written by hand (not via CGPDFContext) because the `/VP` dictionary must be in the page object.
/// Content: areas (transparent fill), north lines, sketch, and bezier lines as vector paths; widths in mm.
///
/// Colours: map symbols and the course overprint are written as DeviceCMYK (`k` / `K`) with the CMYK of the IOF
/// "Printing and Colour Definitions" (Rev 4) × the screen of each colour role (`OccaStandardSymbols.cmyk(forHex:)`);
/// colours of other sets are converted from RGB. Sketches, north lines, basemaps and images stay RGB. The course is
/// painted in the colour order — lower purple below black, blue and brown 100 %, upper purple on top — without
/// multiply blending (Rev 4 §4).
public struct GeoPDFRequest: Sendable {
    public var title: String
    public var frame: MapFrame
    public var sheet: SheetSpec
    public var zone: UTMZone
    public var strokes: [Stroke]
    public var features: [Feature]
    public var grid: NorthGrid?
    /// Course overprint (purple) on top of the map.
    public var overprint: CourseOverprint?
    /// Control description sheet (on the map per `printLayout`, and/or on a second page).
    public var descriptions: DescriptionSheet?
    /// Single-page race map layout; nil = descriptions on a second page (old format).
    public var printLayout: CoursePrintLayout?
    /// Contour interval (informational; not drawn since the title box was removed).
    public var contourIntervalM: Double?
    /// Course object image file contents (JPG/PNG) by file name.
    public var images: [String: Data]
    /// Georeferenced basemap image under the map objects; nil = none.
    public var background: ExportBackground?
    /// Small credit in the bottom-left corner of the map area (Free plan); nil = none.
    public var watermark: String?
    /// Colour priority at which the lower purple course overprint is painted (see `RasterExportRequest`).
    public var overprintLowerPriority = ColorHierarchy.lowerPurplePriority()

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

    /// Full page size (pt) and the map area box inside it (pt, origin bottom-left).
    public static func layout(_ sheet: SheetSpec) -> (page: (w: Double, h: Double), map: (x0: Double, y0: Double, x1: Double, y1: Double)) {
        let m = sheet.marginMM * ptPerMM
        let w = (sheet.mappingWidthMM + 2 * sheet.marginMM) * ptPerMM
        let h = (sheet.mappingHeightMM + 2 * sheet.marginMM) * ptPerMM
        return ((w, h), (m, m, w - m, h - m))
    }

    public static func document(_ req: GeoPDFRequest) -> Data {
        let (page, box) = layout(req.sheet)
        let e = req.frame.extent
        let k = 1000 / Double(req.sheet.scaleDenominator) * ptPerMM  // ground meters → pt
        func pt(_ p: Point2D) -> String { "\(n(box.x0 + (p.x - e.minX) * k)) \(n(box.y0 + (p.y - e.minY) * k))" }

        // MARK: Page content
        var c = "q\n"
        // Clip to the map area.
        c += "\(n(box.x0)) \(n(box.y0)) \(n(box.x1 - box.x0)) \(n(box.y1 - box.y0)) re W n\n"
        c += "1 J 1 j\n"
        // Basemap image under everything: image unit square → page via its corners (bottom left, bottom right, top left).
        let bgImage = req.background.flatMap { bg in CourseImages.pdfImage(bg.imageData).map { (bg, $0) } }
        if let (bg, _) = bgImage, bg.corners.count == 4 {
            func page(_ p: Point2D) -> (Double, Double) { (box.x0 + (p.x - e.minX) * k, box.y0 + (p.y - e.minY) * k) }
            let tl = page(bg.corners[0]), br = page(bg.corners[2]), bl = page(bg.corners[3])
            c += "q /GSBg gs \(n(br.0 - bl.0)) \(n(br.1 - bl.1)) \(n(tl.0 - bl.0)) \(n(tl.1 - bl.1)) \(n(bl.0)) \(n(bl.1)) cm /ImBg Do Q\n"
        }
        let visible = req.features.filter { $0.isVisible && $0.nodes.count >= ($0.kind == .point ? 1 : 2) }
        // Areas: the outer ring and each hole as subpaths, filled/clipped with the even-odd rule (f*, W*).
        func path(_ f: Feature) -> String {
            var s = ""
            for ring in f.ringFeatures where !ring.nodes.isEmpty {
                s += "\(pt(ring.nodes[0].point)) m\n"
                for seg in ring.segments {
                    s += seg.isCurve ? "\(pt(seg.c1)) \(pt(seg.c2)) \(pt(seg.p3)) c\n" : "\(pt(seg.p3)) l\n"
                }
                if f.closesPath { s += "h\n" }
            }
            return s
        }
        func rgb(_ hex: String) -> String {
            let v = rgbComponents(hex: hex) ?? (0, 0, 0)
            return "\(n(v.r)) \(n(v.g)) \(n(v.b))"
        }
        // Map symbols: DeviceCMYK fill / stroke operators; objects without a symbol (sketch areas and lines): RGB.
        func fillOp(_ hex: String, cmyk: Bool = true) -> String { cmyk ? "\(cmykString(hex)) k" : "\(rgb(hex)) rg" }
        func strokeOp(_ hex: String, cmyk: Bool = true) -> String { cmyk ? "\(cmykString(hex)) K" : "\(rgb(hex)) RG" }
        // Point symbols: standard elements × sizeFactor, paper mm → pt.
        func drawPoint(_ f: Feature, level: Int? = nil) {
            guard let node = f.nodes.first else { return }
            let center = node.point
            func at(_ mm: Point2D) -> String {
                let x = box.x0 + (center.x - e.minX) * k + mm.x * ptPerMM
                let y = box.y0 + (center.y - e.minY) * k + mm.y * ptPerMM
                return "\(n(x)) \(n(y))"
            }
            for el in f.scaledPointElements.drawingOrder where level == nil || el.priority == level {
                let o = el.points.first ?? Point2D(x: 0, y: 0)
                switch el.kind {
                case .dot:
                    c += "\(fillOp(el.colorHex))\n\(circlePath(center: o, r: el.diameterMM / 2, at))f\n"
                case .circle:
                    c += "\(strokeOp(el.colorHex)) \(n(el.lineWidthMM * ptPerMM)) w\n\(circlePath(center: o, r: el.diameterMM / 2, at))S\n"
                case .line, .area:
                    guard let first = el.points.first else { continue }
                    var s = "\(at(first)) m\n"
                    for q in el.points.dropFirst() { s += "\(at(q)) l\n" }
                    let ends = el.flatEnds == true ? "0 J 0 j " : ""
                    c += el.kind == .area ? "\(fillOp(el.colorHex))\n\(s)h f\n"
                        : "\(ends)\(strokeOp(el.colorHex)) \(n(el.lineWidthMM * ptPerMM)) w\n\(s)S\n\(ends.isEmpty ? "" : "1 J 1 j\n")"
                }
            }
        }
        // ISOM patterns and decorations as vector marks (page points; marks already positioned).
        func pagePoint(_ p: Point2D) -> Point2D { Point2D(x: box.x0 + (p.x - e.minX) * k, y: box.y0 + (p.y - e.minY) * k) }
        func marks(_ list: [OrnamentMark]) -> String {
            var s = "0 J 0 j [] 0 d\n"
            for m in list {
                switch m {
                case let .line(a, b, w, col):
                    s += "\(strokeOp(col)) \(n(w * ptPerMM)) w \(n(a.x)) \(n(a.y)) m \(n(b.x)) \(n(b.y)) l S\n"
                case let .polyline(pts, w, col):
                    guard let f = pts.first, pts.count > 1 else { continue }
                    s += "\(strokeOp(col)) \(n(w * ptPerMM)) w \(n(f.x)) \(n(f.y)) m " + pts.dropFirst().map { "\(n($0.x)) \(n($0.y)) l " }.joined() + "S\n"
                case let .dot(p, d, col):
                    let r = d * ptPerMM / 2, kk = r * 0.5523
                    s += "\(fillOp(col)) \(n(p.x + r)) \(n(p.y)) m "
                    s += "\(n(p.x + r)) \(n(p.y + kk)) \(n(p.x + kk)) \(n(p.y + r)) \(n(p.x)) \(n(p.y + r)) c "
                    s += "\(n(p.x - kk)) \(n(p.y + r)) \(n(p.x - r)) \(n(p.y + kk)) \(n(p.x - r)) \(n(p.y)) c "
                    s += "\(n(p.x - r)) \(n(p.y - kk)) \(n(p.x - kk)) \(n(p.y - r)) \(n(p.x)) \(n(p.y - r)) c "
                    s += "\(n(p.x + kk)) \(n(p.y - r)) \(n(p.x + r)) \(n(p.y - kk)) \(n(p.x + r)) \(n(p.y)) c f\n"
                case let .polygon(pts, col):
                    guard let f = pts.first else { continue }
                    s += "\(fillOp(col)) \(n(f.x)) \(n(f.y)) m " + pts.dropFirst().map { "\(n($0.x)) \(n($0.y)) l " }.joined() + "h f\n"
                }
            }
            return s
        }
        // Course object images → XObject /Im0, /Im1, …; transparent fills → one ExtGState per opacity.
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
        // The course in the colour order: lower purple below black, blue and brown 100 % (painted when the map's paint
        // order passes its level), upper purple after the map, grid and sketch.
        let overprint = req.overprint?.levels
        var lowerDone = overprint?.lower.isEmpty ?? true
        func drawLower() {
            guard !lowerDone, let o = overprint?.lower else { return }
            lowerDone = true
            c += overprintContent(o, pt: pt, k: k, cmyk: cmykString, images: imageNames, opacities: opacities) + "1 J 1 j [] 0 d\n"
        }
        // Map objects follow the Color Hierarchy (OCAD color table): higher colors cover the colors below them.
        for paint in ColorHierarchy.paintOrder(visible) {
            if paint.priority < req.overprintLowerPriority { drawLower() }
            let f = visible[paint.index]
            switch f.kind {
            case .area:
                if f.isSymbolArea {
                    // Like OCAD/OOM: solid color fill, no outline (pattern-only areas: none), then the ISOM pattern.
                    if !SymbolOrnaments.isPatternOnly(fillHex: f.colorHex, patterns: f.patterns) {
                        c += "\(fillOp(f.colorHex))\n\(path(f))f*\n"
                    }
                    if let patterns = f.patterns, let b = f.bounds {
                        let lo = pagePoint(Point2D(x: b.minX, y: b.minY)), hi = pagePoint(Point2D(x: b.maxX, y: b.maxY))
                        let r = Rect2D(minX: max(lo.x, box.x0), minY: max(lo.y, box.y0), maxX: min(hi.x, box.x1), maxY: min(hi.y, box.y1))
                        if r.maxX > r.minX, r.maxY > r.minY {
                            c += "q\n\(path(f))W* n\n"
                            for p in patterns {
                                if let list = SymbolOrnaments.patternMarks(p, in: r, unitsPerMM: ptPerMM, yUp: true, maxMarks: 200_000,
                                                                           seed: f.patternSeed) {
                                    c += marks(list)
                                }
                            }
                            c += "Q 1 J 1 j\n"
                        }
                    }
                } else {
                    c += "q /GSArea gs \(rgb(f.colorHex)) rg\n\(path(f))f*\nQ\n"
                    c += "1 J 1 j [] 0 d \(rgb(f.colorHex)) RG \(n(f.widthMM * ptPerMM)) w\n\(path(f))S\n"
                }
            case .line:
                // Ends: 0 J / 0 j = butt + miter, 1 J / 1 j = round. Pattern: [dash gap …] 0 d.
                let caps = f.roundCaps == false ? "0 J 0 j" : "1 J 1 j"
                let sym = f.symbolCode != nil
                let dash = f.effectiveDashMM.map { "[\($0.map { n($0 * ptPerMM) }.joined(separator: " "))] 0 d" } ?? "[] 0 d"
                if let casing = f.casingColorHex, let inner = f.innerWidthMM {
                    // Double line: casing and fill each on their own color layer.
                    if paint.part != .main { c += "\(caps) \(dash) \(strokeOp(casing, cmyk: sym)) \(n(f.widthMM * ptPerMM)) w\n\(path(f))S\n" }
                    let innerDash = f.effectiveInnerDashMM.map { "[\($0.map { n($0 * ptPerMM) }.joined(separator: " "))] 0 d" } ?? "[] 0 d"
                    if paint.part != .casing { c += "\(caps) \(innerDash) \(strokeOp(f.colorHex, cmyk: sym)) \(n(inner * ptPerMM)) w\n\(path(f))S\n" }
                } else {
                    if !f.hidesMainLine { c += "\(caps) \(dash) \(strokeOp(f.colorHex, cmyk: sym)) \(n(f.widthMM * ptPerMM)) w\n\(path(f))S\n" }
                    if let deco = f.decoration {
                        let pts = SymbolOrnaments.polyline(f, pagePoint)
                        c += marks(SymbolOrnaments.decorationMarks(deco, along: pts, unitsPerMM: ptPerMM, lineWidthMM: f.widthMM,
                                                                   colorHex: f.colorHex, yUp: true, dashMM: f.effectiveDashMM)) + "\(caps)\n"
                    }
                }
            case .point:
                c += "1 J 1 j [] 0 d\n"
                var level: Int?
                if case let .elements(l) = paint.part { level = l }
                drawPoint(f, level: level)
            }
        }
        drawLower()
        c += "1 J 1 j [] 0 d\n"
        // North grid and pencil sketch on top of the map objects.
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
        if let o = overprint?.upper, !o.isEmpty {
            c += overprintContent(o, pt: pt, k: k, cmyk: cmykString, images: imageNames, opacities: opacities)
        }
        if let text = req.background?.attribution, !text.isEmpty, bgImage != nil {
            let w = Double(text.count) * 5 * 0.5
            // Credit at the bottom right of the map area, on a white strip (Helvetica 5 pt ≈ 2.5 pt per character).
            c += "q 1 1 1 rg \(n(box.x1 - w - 4)) \(n(box.y0 + 1)) \(n(w + 3)) 7 re f Q\n"
            c += "BT /F1 5 Tf 0.25 0.25 0.25 rg \(n(box.x1 - w - 2.5)) \(n(box.y0 + 2.8)) Td (\(pdfString(text))) Tj ET\n"
        }
        if let mark = req.watermark, !mark.isEmpty {
            // Bottom-left of the map area on a white strip (Helvetica 6 pt ≈ 3 pt per character).
            let w = Double(mark.count) * 6 * 0.5
            c += "q 1 1 1 rg \(n(box.x0 + 1)) \(n(box.y0 + 1)) \(n(w + 5)) 8.5 re f Q\n"
            c += "BT /F2 6 Tf 0.2 0.2 0.2 rg \(n(box.x0 + 3.5)) \(n(box.y0 + 3.2)) Td (\(pdfString(mark))) Tj ET\n"
        }
        c += "Q\n"
        // Race map: control descriptions on top of the map (inside the map area).
        if let layout = req.printLayout, let d = req.descriptions {
            c += decorations(layout, sheet: d, req: req, box: box)
        }
        // Map area border + caption in the bottom margin (if there is a margin).
        c += "0.6 0.6 0.6 RG 0.3 w \(n(box.x0)) \(n(box.y0)) \(n(box.x1 - box.x0)) \(n(box.y1 - box.y0)) re S\n"
        if req.sheet.marginMM >= 4 {
            let caption = "\(req.title) · 1:\(req.sheet.scaleDenominator) · \(req.zone.label) (EPSG:\(req.zone.epsg)) · \(AppInfo.name)"
            c += "BT /F1 6 Tf 0.35 0.35 0.35 rg \(n(box.x0)) \(n(box.y0 - 8)) Td (\(pdfString(caption))) Tj ET\n"
        }

        // MARK: Georeferencing
        // LPTS = viewport box corners in normalized coordinates; GPTS = lat lon of the same corners.
        let lpts: [(Double, Double)] = [(0, 0), (0, 1), (1, 1), (1, 0)]
        let corners = [Point2D(x: e.minX, y: e.minY), Point2D(x: e.minX, y: e.maxY), Point2D(x: e.maxX, y: e.maxY), Point2D(x: e.maxX, y: e.minY)]
        let gpts = corners.map { req.zone.unproject($0) }.map { "\(n($0.lat, 9)) \(n($0.lon, 9))" }.joined(separator: " ")
        let lptsString = lpts.map { "\(n($0.0)) \(n($0.1))" }.joined(separator: " ")

        // MARK: PDF objects
        let content = Data(c.utf8)
        var objects: [Data] = []
        func add(_ s: String) -> Int { objects.append(Data(s.utf8)); return objects.count }
        let catalog = add("") // filled in once pages are known
        let pages = add("")
        let gcs = add("<< /Type /PROJCS /EPSG \(req.zone.epsg) /WKT (\(pdfString(req.zone.prjWKT))) >>")
        let measure = add("<< /Type /Measure /Subtype /GEO /Bounds [0 0 0 1 1 1 1 0] /GPTS [\(gpts)] /LPTS [\(lptsString)] /GCS \(gcs) 0 R /PDU [/M /SQM /DEG] >>")
        let font = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        let bold = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
        let oblique = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique /Encoding /WinAnsiEncoding >>")
        let boldOblique = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-BoldOblique /Encoding /WinAnsiEncoding >>")
        func addStream(_ dict: String, _ body: Data) -> Int {
            objects.append(Data("<< \(dict) /Length \(body.count) >>\nstream\n".utf8) + body + Data("\nendstream".utf8))
            return objects.count
        }
        var xobjects: [String] = []
        if let (_, img) = bgImage {
            var dict = img.dictionary
            if let m = img.mask { dict += " /SMask \(addStream(m.dictionary, m.stream)) 0 R" }
            xobjects.append("/ImBg \(addStream(dict, img.stream)) 0 R")
        }
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
        /Resources << /Font << /F1 \(font) 0 R /F2 \(bold) 0 R /F3 \(oblique) 0 R /F4 \(boldOblique) 0 R >> /XObject << \(xobjects.joined(separator: " ")) >> \
        /ExtGState << /GSBg << /Type /ExtGState /ca \(n(req.background?.opacity ?? 1)) >> /GSArea << /Type /ExtGState /ca 0.35 >> /GSGrid << /Type /ExtGState /CA \(gridOpacity) >> \
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
            extraPages.append(add("<< /Type /Page /Parent \(pages) 0 R /MediaBox [0 0 595.276 841.89] /Contents \(streamObj) 0 R /Resources << /Font << /F1 \(font) 0 R /F2 \(bold) 0 R /F3 \(oblique) 0 R /F4 \(boldOblique) 0 R >> >> >>"))
        }
        let kids = ([pageObj] + extraPages).map { "\($0) 0 R" }.joined(separator: " ")
        objects[pages - 1] = Data("<< /Type /Pages /Kids [\(kids)] /Count \(1 + extraPages.count) >>".utf8)
        let info = add("<< /Title (\(pdfString(req.title))) /Producer (\(AppInfo.name)) /Creator (\(AppInfo.name)) >>")

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

    // MARK: Courses

    /// Purple overprint: circles, start triangle, legs, and numbers (Helvetica, digit height = IOF number height).
    /// `cmyk`: hex → "c m y k" (DeviceCMYK); purple is the IOF 35/85/0/0. No blend mode: the caller places the lower
    /// and upper purple parts in the colour order (`CourseOverprint.levels`).
    static func overprintContent(_ o: CourseOverprint, pt: (Point2D) -> String, k: Double, cmyk: (String) -> String,
                                 images: [String: String] = [:], opacities: [Double] = []) -> String {
        var c = "q 1 J 1 j [] 0 d \(cmyk(o.colorHex)) K \(cmyk(o.colorHex)) k \(n(o.lineWidthM * k)) w\n"
        func xy(_ p: Point2D) -> (Double, Double)? {
            let v = pt(p).split(separator: " ").compactMap { Double($0) }
            return v.count == 2 ? (v[0], v[1]) : nil
        }
        var font = "F1"
        for mark in o.marks {
            switch mark {
            case let .font(bold, italic):
                font = bold ? (italic ? "F4" : "F2") : (italic ? "F3" : "F1")
            case let .color(hex):
                let v = cmyk(hex ?? o.colorHex)
                c += "\(v) K \(v) k\n"
            case let .width(w):
                c += "\(n((w ?? o.lineWidthM) * k)) w\n"
            case .level:
                break
            case let .circle(center, r):
                c += circlePath(center: center, r: r, pt) + "S\n"
            case let .polyline(pts, closed):
                guard let first = pts.first else { continue }
                c += "\(pt(first)) m\n" + pts.dropFirst().map { "\(pt($0)) l\n" }.joined() + (closed ? "h\n" : "") + "S\n"
            case let .text(text, center, h):
                // Helvetica digit height ≈ 0.72 em; digit width 0.556 em.
                let size = h * k / 0.72
                let w = Double(text.count) * 0.556 * size
                let xy = pt(center).split(separator: " ").compactMap { Double($0) }
                guard xy.count == 2 else { continue }
                c += "BT /\(font) \(n(size)) Tf \(n(xy[0] - w / 2)) \(n(xy[1] - h * k / 2)) Td (\(pdfString(text))) Tj ET\n"
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

    /// DeviceCMYK components (0–1) of a colour: the IOF spec CMYK × screen for OCCA's colours, else converted from RGB.
    static func cmykString(_ hex: String) -> String {
        let v = OccaStandardSymbols.cmyk(forHex: hex) ?? SymbolSet.cmyk(fromHex: hex)
        return v.prefix(4).map { n($0) }.joined(separator: " ")
    }

    /// A4 page with the description table (7 mm cells) at the top left.
    static func descriptionContent(_ d: DescriptionSheet, maxRows: Int? = nil, symbols: Bool = true,
                                   color: CoursePrintLayout.DescriptionColor = .black) -> String {
        let cell = 7 * ptPerMM
        var c = "", height = 0.0
        for (i, col) in d.columns(maxRows: maxRows).enumerated() {
            let (table, h) = descriptionTable(col, x0: 40 + Double(i) * cell * 8, yTop: 800, cell: cell, background: false, symbols: symbols, color: color)
            c += table
            height = max(height, h)
        }
        return c + "BT /F1 6 Tf 40 \(n(800 - height - 14)) Td (\(pdfString("\(AppInfo.name) · IOF control descriptions \(symbols ? "2024" : "(text)")"))) Tj ET\n"
    }

    /// Description table height (pt) for cell size `cell`.
    static func descriptionTableHeight(_ d: DescriptionSheet, cell: Double) -> Double {
        Double(d.rows.count + d.headingRowCount + (d.isContinuation ? 0 : 1)) * cell
    }

    /// Distance of the description block from the map area edge when in a corner (mm).
    public static let descriptionInsetMM = 4.0

    /// Description block size on paper (mm): columns side by side, height = tallest column.
    public static func descriptionBlockSizeMM(_ d: DescriptionSheet, layout: CoursePrintLayout) -> (w: Double, h: Double) {
        let cell = clampedCellMM(layout)
        let cols = d.columns(maxRows: layout.descriptionMaxRows)
        return (Double(cols.count) * cell * 8, cols.map { descriptionTableHeight($0, cell: cell) }.max() ?? 0)
    }

    /// Top-left corner of the description block from the top-left of the map area (mm), inside the map area.
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

    /// Description table: column A (number), B (code), then C–H as IOF pictograms (`symbols`) or a text description spanning
    /// 6 cells; 14.1/15.x/16.x as full-width rows; thick lines per `Row.thickBelow`. `background`: white fill (for placing on
    /// top of the map).
    static func descriptionTable(_ d: DescriptionSheet, x0: Double, yTop: Double, cell: Double, background: Bool,
                                 symbols: Bool = true, color: CoursePrintLayout.DescriptionColor = .black) -> (String, Double) {
        let s = cell / (7 * ptPerMM)  // font size follows the cell size
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
        if !d.isContinuation, !d.classes.isEmpty {
            y -= cell
            box(x0, y, width, cell)
            text(fit(d.classes, width: width - 4, size: 7.5 * s), x: x0, y: y + cell * 0.34, size: 7.5 * s, center: true, maxWidth: width)
        }
        if !d.isContinuation {
            y -= cell
            box(x0, y, cell * 4, cell); box(x0 + cell * 4, y, cell * 2, cell); box(x0 + cell * 6, y, cell * 2, cell)
            text(fit(d.courseName, width: cell * 4 - 4, size: 9 * s, bold: true), x: x0 + 3 * s, y: y + cell * 0.32, size: 9 * s, font: "F2")
            text(d.lengthText, x: x0 + cell * 4, y: y + cell * 0.32, size: 8 * s, center: true, maxWidth: cell * 2)
            text(d.climbText, x: x0 + cell * 6, y: y + cell * 0.32, size: 8 * s, center: true, maxWidth: cell * 2)
        }

        func thickLine(_ row: DescriptionSheet.Row, _ y: Double) {
            if row.thickBelow { c += "\(n(1.5 * s)) w \(n(x0)) \(n(y)) m \(n(x0 + width)) \(n(y)) l S \(n(0.5 * s)) w\n" }
        }
        for row in d.rows {
            y -= cell
            if row.isFullWidth(symbols: symbols) {
                box(x0, y, width, cell)
                if symbols, let shapes = IOFPictogram.rowShapes(row) {
                    c += IOFPictogram.pdf(shapes, x0: x0, y0: y, size: cell, textWidth: { textWidth($0, size: $1) })
                } else {
                    // Text line across the whole row: 1–2 lines.
                    let one = wrap(row.text, maxChars: 46), two = wrap(row.text, maxChars: 56)
                    if one.count <= 1 {
                        text(one.first ?? "", x: x0 + 3 * s, y: y + cell * 0.32, size: 7 * s)
                    } else {
                        text(two[0], x: x0 + 3 * s, y: y + cell * 0.56, size: 5.8 * s)
                        text(two.count > 2 ? two[1] + "..." : two[1], x: x0 + 3 * s, y: y + cell * 0.14, size: 5.8 * s)
                    }
                }
                thickLine(row, y)
                continue
            }
            box(x0, y, cell, cell); box(x0 + cell, y, cell, cell)
            if symbols {
                // C–H: one cell per column; thick lines after C and F like the IOF sheet.
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
                // Columns that are not filled are left empty.
                thickLine(row, y)
                continue
            }
            // Description: 1–2 lines, smaller font when long.
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
            thickLine(row, y)
        }
        c += "\(n(1.5 * s)) w \(n(x0)) \(n(y)) \(n(width)) \(n(yTop - y)) re S\nQ\n"
        return (c, height)
    }

    /// Helvetica text width (estimate from average character width).
    static func textWidth(_ s: String, size: Double, bold: Bool = false) -> Double {
        Double(s.count) * size * (bold ? 0.58 : 0.52)
    }

    /// Truncate text to fit the width (pt), with "...".
    static func fit(_ s: String, width: Double, size: Double, bold: Bool = false) -> String {
        guard textWidth(s, size: size, bold: bold) > width else { return s }
        var t = s
        while !t.isEmpty, textWidth(t + "...", size: size, bold: bold) > width { t.removeLast() }
        return t + "..."
    }

    /// A readable scale bar length (m): 15–30 mm on paper.
    public static func scaleBarMeters(scale: Int) -> Double {
        let options: [Double] = [10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000]
        let mm = { (m: Double) in m * 1000 / Double(scale) }
        return options.last { mm($0) <= 30 } ?? options[0]
    }

    // MARK: Race map (single page)

    /// Control descriptions on top of the map (white background): in the chosen corner or a free position, split into several
    /// side-by-side columns when rows exceed the per-column limit.
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

    /// Circle as 4 cubic curves (kappa), mm coordinates relative to the symbol center.
    static func circlePath(center o: Point2D, r: Double, _ at: (Point2D) -> String) -> String {
        let k = Feature.ellipseKappa * r
        func p(_ x: Double, _ y: Double) -> String { at(Point2D(x: o.x + x, y: o.y + y)) }
        return "\(p(r, 0)) m\n\(p(r, k)) \(p(k, r)) \(p(0, r)) c\n\(p(-k, r)) \(p(-r, k)) \(p(-r, 0)) c\n"
            + "\(p(-r, -k)) \(p(-k, -r)) \(p(0, -r)) c\n\(p(k, -r)) \(p(r, -k)) \(p(r, 0)) c\nh\n"
    }

    /// PDF number: decimal point, no trailing zeros. Integer arithmetic, not `String(format:)`
    /// (a race map PDF contains hundreds of thousands of numbers; performance test: 4 s → much faster).
    static func n(_ v: Double, _ decimals: Int = 3) -> String {
        guard v.isFinite else { return "0" }
        let d = min(max(decimals, 0), 9)
        let p = pow10[d]
        // Round half to even like printf (0.5 → 0; 0.125 → 0.12).
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

    /// PDF string literal: escape \ ( ) and replace non-Latin-1 characters (standard fonts use WinAnsi).
    static func pdfString(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "(": out += "\\("
            case ")": out += "\\)"
            default:
                // WinAnsiEncoding equals Latin-1 for 0xA0–0xFF (©, ·, ×, é …): octal escape; other characters → "?".
                if u.value < 128 { out += String(u) } else if (160...255).contains(u.value) { out += "\\" + String(u.value, radix: 8) } else { out += "?" }
            }
        }
        return out
    }
}
