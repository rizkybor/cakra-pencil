import CakraCore
import MapKit
import UIKit

/// Field report (PDF, A4): summary, an overview map with the tracks and numbered notes, then every note with its
/// details and photos. For the club, the event controller, or the mapper's own records. iPad and Mac.
extension WorkspaceModel {
    /// `saveTo`: write the PDF there instead of the save dialog (UI tests).
    func exportFieldReport(saveTo target: URL? = nil) async {
        guard LicenseManager.shared.require(.fieldReport) else { return }
        guard let zone, !field.isEmpty else { return }
        notice = "Making the field report…"
        let overview = await FieldReport.overview(field: field, zone: zone, frame: frameRect)
        let coverage: Double? = await {
            guard let area = frameRect, !field.tracks.isEmpty else { return nil }
            let tracks = field.tracks, r = field.coverageRadius
            return await Task.detached(priority: .userInitiated) { FieldCoverage.fraction(of: area, tracks: tracks, radiusM: r) }.value
        }()
        do {
            let dir = TempExports.newDirectory()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(projectFileName(project.name))_field-report").appendingPathExtension("pdf")
            var report = FieldReport(projectName: project.name, scale: project.sheet.scaleDenominator, zone: zone, field: field,
                                     coverage: coverage, overview: overview, frame: frameRect,
                                     photoURL: { [weak self] in self?.fieldPhotoURL($0) })
            report.markupURL = { [weak self] note, photo in self?.markupURL(photo, in: note) }
            try report.render().write(to: target ?? file, options: .atomic)
            notice = target == nil ? nil : "Field report saved."
            if target == nil { DocumentExport.present(file) }
        } catch {
            notice = "Couldn't make the field report: \(error.localizedDescription)"
        }
    }
}

struct FieldReport {
    let projectName: String
    let scale: Int
    let zone: UTMZone
    let field: FieldData
    let coverage: Double?
    let overview: Overview?
    /// The map frame, outlined on the overview.
    var frame: Rect2D? = nil
    let photoURL: (String) -> URL?
    /// The markup drawing of a note's photo, drawn on top in the report.
    var markupURL: (FieldNote, String) -> URL? = { _, _ in nil }

    /// Overview map image with a projection from UTM to image points.
    struct Overview {
        var image: UIImage
        var point: (Point2D) -> CGPoint
    }

    static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)   // A4 in points
    static let margin: CGFloat = 44

    /// Notes in the order they were made; numbers match the map.
    var notes: [FieldNote] { field.notes.sorted { $0.createdAt < $1.createdAt } }

    // MARK: Overview map

    /// Apple Maps satellite snapshot of the field data (and the frame), or a plain background when offline.
    static func overview(field: FieldData, zone: UTMZone, frame: Rect2D?) async -> Overview? {
        var pts = field.tracks.flatMap { $0.points.map(\.position) } + field.notes.map(\.position)
        if let f = frame { pts += [Point2D(x: f.minX, y: f.minY), Point2D(x: f.maxX, y: f.maxY)] }
        guard var box = Rect2D(points: pts) else { return nil }
        let pad = max(40, max(box.maxX - box.minX, box.maxY - box.minY) * 0.06)
        box = Rect2D(minX: box.minX - pad, minY: box.minY - pad, maxX: box.maxX + pad, maxY: box.maxY + pad)
        let size = CGSize(width: page.width - 2 * margin, height: 330)

        let sw = zone.unproject(Point2D(x: box.minX, y: box.minY)), ne = zone.unproject(Point2D(x: box.maxX, y: box.maxY))
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (sw.lat + ne.lat) / 2, longitude: (sw.lon + ne.lon) / 2),
                                            span: MKCoordinateSpan(latitudeDelta: abs(ne.lat - sw.lat), longitudeDelta: abs(ne.lon - sw.lon)))
        options.size = size
        options.scale = 2
        options.mapType = .satellite
        let snapshot: MKMapSnapshotter.Snapshot? = await withTaskGroup(of: MKMapSnapshotter.Snapshot?.self) { group in
            group.addTask { try? await MKMapSnapshotter(options: options).start() }
            group.addTask { try? await Task.sleep(for: .seconds(12)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let snapshot {
            return Overview(image: snapshot.image) { p in
                let ll = zone.unproject(p)
                return snapshot.point(for: CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
            }
        }
        // Offline: a plain background, UTM scaled to fit.
        let k = min(size.width / (box.maxX - box.minX), size.height / (box.maxY - box.minY))
        let ox = (size.width - (box.maxX - box.minX) * k) / 2, oy = (size.height - (box.maxY - box.minY) * k) / 2
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.95, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return Overview(image: image) { p in CGPoint(x: ox + (p.x - box.minX) * k, y: size.height - oy - (p.y - box.minY) * k) }
    }

    // MARK: Render

    func render() -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Field report — \(projectName)", kCGPDFContextCreator as String: AppInfo.name]
        return UIGraphicsPDFRenderer(bounds: Self.page, format: format).pdfData { ctx in
            var y = Self.margin
            ctx.beginPage()
            y = header(y)
            y = summary(y)
            y = overviewMap(y, ctx: ctx)
            if !notes.isEmpty {
                y = newPageIfNeeded(y, need: 60, ctx: ctx)
                y = text("Field notes", at: y, font: .boldSystemFont(ofSize: 15)) + 6
                for (i, n) in notes.enumerated() { y = note(i + 1, n, y: y, ctx: ctx) }
            }
            footer()
        }
    }

    private var width: CGFloat { Self.page.width - 2 * Self.margin }

    @discardableResult
    private func text(_ s: String, at y: CGFloat, x: CGFloat = FieldReport.margin, width w: CGFloat? = nil, font: UIFont = .systemFont(ofSize: 10),
                      color: UIColor = .black) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let box = CGRect(x: x, y: y, width: w ?? width, height: 10_000)
        let h = (s as NSString).boundingRect(with: box.size, options: [.usesLineFragmentOrigin], attributes: attrs, context: nil).height
        (s as NSString).draw(with: CGRect(x: x, y: y, width: box.width, height: ceil(h)), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        return y + ceil(h)
    }

    private func newPageIfNeeded(_ y: CGFloat, need: CGFloat, ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        guard y + need > Self.page.height - Self.margin - 20 else { return y }
        footer()
        ctx.beginPage()
        return Self.margin
    }

    private func footer() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM yyyy HH:mm"
        text("\(projectName) — field report · \(AppInfo.name) · \(f.string(from: Date()))", at: Self.page.height - Self.margin + 14,
             font: .systemFont(ofSize: 8), color: .gray)
    }

    private func header(_ y: CGFloat) -> CGFloat {
        var y = text("Field report", at: y, font: .boldSystemFont(ofSize: 22))
        y = text("\(projectName) · 1:\(scale) · UTM zone \(zone.number)\(zone.isNorth ? "N" : "S") (WGS 84)", at: y + 2,
                 font: .systemFont(ofSize: 11), color: .darkGray)
        return y + 14
    }

    private func summary(_ y: CGFloat) -> CGFloat {
        let tracks = field.tracks
        let length = tracks.reduce(0) { $0 + $1.lengthM }
        let time = tracks.compactMap(\.duration).reduce(0, +)
        let todo = field.notes.filter { !$0.isDone }.count
        let veg = field.notes.filter { $0.vegetation != nil }.count
        var rows: [(String, String)] = [
            ("Tracks", "\(tracks.count) · \(TrackLineEditor.meters(length))" + (time > 0 ? " · \(Self.duration(time)) recorded" : "")),
            ("Field notes", "\(field.notes.count) (\(todo) to do, \(field.notes.count - todo) done)"
                + (field.photoFiles.isEmpty ? "" : " · \(field.photoFiles.count) photo\(field.photoFiles.count == 1 ? "" : "s")")),
        ]
        if veg > 0 { rows.append(("Vegetation samples", "\(veg)")) }
        if let c = coverage { rows.append(("Survey coverage", "\(Int((c * 100).rounded())) % of the map area (±\(Int(field.coverageRadius)) m each side)")) }
        if let first = (tracks.compactMap(\.startTime) + field.notes.map(\.createdAt)).min(),
           let last = (tracks.compactMap(\.endTime) + field.notes.map(\.createdAt)).max() {
            rows.append(("Fieldwork", "\(FieldNoteDetail.dateText(first)) – \(FieldNoteDetail.dateText(last))"))
        }
        var y = y
        for (k, v) in rows {
            text(k, at: y, width: 130, font: .boldSystemFont(ofSize: 10), color: .darkGray)
            y = text(v, at: y, x: Self.margin + 130, width: width - 130) + 3
        }
        return y + 12
    }

    private func overviewMap(_ y: CGFloat, ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        guard let ov = overview else { return y }
        let rect = CGRect(x: Self.margin, y: y, width: width, height: ov.image.size.height)
        let cg = ctx.cgContext
        ov.image.draw(in: rect)
        cg.saveGState()
        cg.clip(to: rect)
        cg.translateBy(x: rect.minX, y: rect.minY)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        if let f = frame {
            let corners = [Point2D(x: f.minX, y: f.minY), Point2D(x: f.maxX, y: f.minY), Point2D(x: f.maxX, y: f.maxY), Point2D(x: f.minX, y: f.maxY)]
            let path = CGMutablePath()
            path.addLines(between: corners.map(ov.point))
            path.closeSubpath()
            cg.addPath(path); cg.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor); cg.setLineWidth(1.6); cg.strokePath()
            cg.addPath(path); cg.setStrokeColor(UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1).cgColor); cg.setLineWidth(0.8)
            cg.setLineDash(phase: 0, lengths: [4, 3]); cg.strokePath(); cg.setLineDash(phase: 0, lengths: [])
        }
        for t in field.tracks {
            for seg in t.segments where seg.count > 1 {
                let path = CGMutablePath()
                path.addLines(between: seg.map { ov.point($0.position) })
                cg.addPath(path); cg.setStrokeColor(UIColor.white.cgColor); cg.setLineWidth(3.2); cg.strokePath()
                cg.addPath(path); cg.setStrokeColor(UIColor(hexString: t.colorHex).cgColor); cg.setLineWidth(1.8); cg.strokePath()
            }
        }
        for (i, n) in notes.enumerated() {
            let c = ov.point(n.position), r: CGFloat = 7
            let color = UIColor(hexString: n.vegetation?.colorHex ?? n.category.colorHex)
            cg.setFillColor(UIColor.white.cgColor); cg.fillEllipse(in: CGRect(x: c.x - r - 1, y: c.y - r - 1, width: 2 * r + 2, height: 2 * r + 2))
            cg.setFillColor(color.cgColor); cg.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            let label = "\(i + 1)" as NSString
            let dark = n.vegetation != nil && n.vegetation != .fight
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 7.5), .foregroundColor: dark ? UIColor.black : UIColor.white]
            let s = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: c.x - s.width / 2, y: c.y - s.height / 2), withAttributes: attrs)
        }
        cg.restoreGState()
        cg.setStrokeColor(UIColor.lightGray.cgColor)
        cg.setLineWidth(0.5)
        cg.stroke(rect)
        let caption = (frame != nil ? "Red dashed line: map frame · " : "") + "Lines: GPS tracks · Numbers: the field notes below"
        return text(caption, at: rect.maxY + 4, font: .systemFont(ofSize: 8), color: .gray) + 16
    }

    private func note(_ number: Int, _ n: FieldNote, y: CGFloat, ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        let photoH: CGFloat = n.photos.isEmpty ? 0 : 104
        var y = newPageIfNeeded(y, need: 70 + photoH, ctx: ctx)
        let status = n.isDone ? "done" : "to do"
        y = text("\(number). \(n.title)", at: y, font: .boldSystemFont(ofSize: 11))
        var lines = ["\(n.vegetation.map { "\($0.code) \($0.label)" } ?? n.category.label) · \(status) · \(FieldNoteDetail.dateText(n.createdAt))",
                     FieldNoteDetail.positionText(n.position, zone: zone)]
        if let a = n.averaging {
            lines.append("Averaged ±\(Fmt.number(a.accuracyM, decimals: 1)) m from \(a.samples) fixes")
        } else if let acc = n.accuracyM {
            lines.append("GPS ±\(Int(acc.rounded())) m")
        }
        if let o = n.offset { lines.append("Offset \(FieldNoteDetail.distanceText(o.distanceM)) at \(FieldNoteDetail.headingText(o.bearingDeg))") }
        if let h = n.photoHeadingDeg { lines.append("Camera facing \(FieldNoteDetail.headingText(h))") }
        y = text(lines.joined(separator: "\n"), at: y + 1, font: .systemFont(ofSize: 9), color: .darkGray)
        // The text without its first line when that is already the title.
        var body = n.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if body.first?.trimmingCharacters(in: .whitespaces) == n.title { body.removeFirst() }
        let rest = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { y = text(rest, at: y + 2, font: .systemFont(ofSize: 10)) }
        if !n.photos.isEmpty {
            var x = Self.margin
            let h: CGFloat = 96
            for name in n.photos.prefix(4) {
                guard let url = photoURL(name), let img = FieldPhotoImage.load(photo: url, markup: markupURL(n, name)) else { continue }
                let w = min(h * img.size.width / max(img.size.height, 1), (width - 24) / 4)
                let r = CGRect(x: x, y: y + 4, width: w, height: h)
                img.preparingThumbnail(of: CGSize(width: w * 3, height: h * 3))?.draw(in: r)
                x += w + 8
            }
            y += h + 6
        }
        return y + 12
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(max(m, 1)) min"
    }
}
