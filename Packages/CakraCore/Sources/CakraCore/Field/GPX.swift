import Foundation

/// GPX 1.1 export and import of field data (tracks ↔ `<trk>`, notes ↔ `<wpt>`), for GPS watches and other apps
/// (Garmin, Suunto, Coros, OOM, QGIS). Coordinates are WGS84 lat/lon; OCCA stores UTM in the project's zone.
public enum GPX {
    // MARK: Export

    public static func export(_ field: FieldData, zone: UTMZone, name: String) -> String {
        let iso = ISO8601DateFormatter()
        func coord(_ p: Point2D) -> String {
            let ll = zone.unproject(p)
            return "lat=\"\(String(format: "%.7f", ll.lat))\" lon=\"\(String(format: "%.7f", ll.lon))\""
        }
        var x = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="\(escape(AppInfo.name))" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(escape(name))</name></metadata>

        """
        for n in field.notes {
            x += "  <wpt \(coord(n.position))>"
            x += "<time>\(iso.string(from: n.createdAt))</time>"
            x += "<name>\(escape(n.title))</name>"
            var desc = [n.category.label]
            if !n.text.isEmpty { desc.append(n.text) }
            if let a = n.averaging { desc.append("Averaged: \(a.samples) fixes, ±\(String(format: "%.1f", a.accuracyM)) m") }
            x += "<desc>\(escape(desc.joined(separator: " — ")))</desc>"
            x += "<type>\(n.category.rawValue)</type>"
            x += "</wpt>\n"
        }
        for t in field.tracks where !t.points.isEmpty {
            // One <trkseg> per recorded segment (pause / resume), as GPS devices do.
            x += "  <trk><name>\(escape(t.name))</name>\n"
            for seg in t.segments {
                x += "   <trkseg>\n"
                for p in seg {
                    x += "    <trkpt \(coord(p.position))>"
                    if let e = p.elevationM { x += "<ele>\(String(format: "%.1f", e))</ele>" }
                    if let time = p.time { x += "<time>\(iso.string(from: time))</time>" }
                    if let a = p.accuracyM { x += "<hdop>\(String(format: "%.1f", a / 5))</hdop>" }
                    x += "</trkpt>\n"
                }
                x += "   </trkseg>\n"
            }
            x += "  </trk>\n"
        }
        return x + "</gpx>\n"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: Import

    public enum ReadError: LocalizedError {
        case notGPX, empty
        public var errorDescription: String? {
            switch self {
            case .notGPX: return "This is not a GPX file."
            case .empty: return "The GPX file has no tracks or waypoints."
            }
        }
    }

    /// Tracks (`<trk>` and `<rte>`) and waypoints (`<wpt>`, as field notes) in the project's zone. Imported tracks get
    /// colors from the palette after `existingTracks`.
    public static func read(_ data: Data, zone: UTMZone, existingTracks: Int = 0, fileName: String = "GPX") throws -> (tracks: [FieldTrack], notes: [FieldNote]) {
        let p = Parser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.shouldResolveExternalEntities = false
        guard xml.parse(), p.isGPX else { throw ReadError.notGPX }
        var tracks: [FieldTrack] = []
        for (i, t) in p.tracks.enumerated() where !t.points.isEmpty {
            let pts = t.points.map { FieldTrack.Point(position: zone.project(LatLon(lat: $0.lat, lon: $0.lon)), time: $0.time,
                                                      elevationM: $0.ele, startsSegment: $0.newSegment ? true : nil) }
            let name = t.name.isEmpty ? (p.tracks.count > 1 ? "\(fileName) \(i + 1)" : fileName) : t.name
            tracks.append(FieldTrack(name: name, colorHex: FieldTrack.palette[(existingTracks + tracks.count) % FieldTrack.palette.count],
                                     points: pts, source: "gpx"))
        }
        let notes = p.waypoints.map { w in
            FieldNote(position: zone.project(LatLon(lat: w.lat, lon: w.lon)), createdAt: w.time ?? Date(),
                      category: FieldNote.Category(rawValue: w.type) ?? .other,
                      text: [w.name, w.desc].filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        guard !tracks.isEmpty || !notes.isEmpty else { throw ReadError.empty }
        return (tracks, notes)
    }

    private final class Parser: NSObject, XMLParserDelegate {
        struct RawPoint { var lat = 0.0, lon = 0.0, ele: Double?, time: Date?, newSegment = false }
        struct RawTrack { var name = ""; var points: [RawPoint] = [] }
        struct RawWaypoint { var lat = 0.0, lon = 0.0, time: Date?, name = "", desc = "", type = "" }

        var isGPX = false
        var tracks: [RawTrack] = []
        var waypoints: [RawWaypoint] = []
        private var track: RawTrack?
        private var point: RawPoint?
        private var waypoint: RawWaypoint?
        /// The next track point starts a new <trkseg> (not the first one of the track).
        private var segmentBreak = false
        private var text = ""
        private let iso = ISO8601DateFormatter()
        private let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()

        private func date(_ s: String) -> Date? { iso.date(from: s) ?? isoFrac.date(from: s) }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes a: [String: String] = [:]) {
            text = ""
            switch name {
            case "gpx": isGPX = true
            case "trk", "rte": track = RawTrack(); segmentBreak = false
            case "trkseg": segmentBreak = !(track?.points.isEmpty ?? true)
            case "trkpt", "rtept":
                point = RawPoint(lat: Double(a["lat"] ?? "") ?? .nan, lon: Double(a["lon"] ?? "") ?? .nan)
            case "wpt":
                waypoint = RawWaypoint(lat: Double(a["lat"] ?? "") ?? .nan, lon: Double(a["lon"] ?? "") ?? .nan)
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "ele":
                if point != nil { point?.ele = Double(t) }
            case "time":
                if point != nil { point?.time = date(t) } else if waypoint != nil { waypoint?.time = date(t) }
            case "name":
                if waypoint != nil { waypoint?.name = t } else if point == nil, track != nil { track?.name = t }
            case "desc":
                if waypoint != nil { waypoint?.desc = t }
            case "type":
                if waypoint != nil { waypoint?.type = t }
            case "trkpt", "rtept":
                if var p = point, p.lat.isFinite, p.lon.isFinite, abs(p.lat) <= 90, abs(p.lon) <= 180 {
                    p.newSegment = segmentBreak
                    segmentBreak = false
                    track?.points.append(p)
                }
                point = nil
            case "trk", "rte":
                if let tr = track { tracks.append(tr) }
                track = nil
            case "wpt":
                if let w = waypoint, w.lat.isFinite, w.lon.isFinite, abs(w.lat) <= 90, abs(w.lon) <= 180 { waypoints.append(w) }
                waypoint = nil
            default: break
            }
            text = ""
        }
    }
}
