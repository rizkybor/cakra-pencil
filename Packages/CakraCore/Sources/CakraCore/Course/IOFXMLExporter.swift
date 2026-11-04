import Foundation

/// Export lintasan ke IOF XML 3.0 `CourseData` (dibaca MeOS, OE/SportSoftware, SI Config/SportIdent, Purple Pen,
/// OCAD): posisi kontrol (lat/lon + mm peta), urutan, panjang leg, panjang/tanjakan lintasan, jumlah peserta.
public enum IOFXMLExporter {
    public static func courseData(_ set: CourseSet, frame: MapFrame, sheet: SheetSpec, zone: UTMZone,
                                  createTime: Date = Date(), creator: String = "Cakra Pencil") -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let e = frame.extent
        let mmPerM = 1000 / Double(sheet.scaleDenominator)
        func f(_ v: Double, _ d: Int = 2) -> String { GeoPDFExporter.n(v, d) }

        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        x += "<CourseData xmlns=\"http://www.orienteering.org/datastandard/3.0\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
        x += "iofVersion=\"3.0\" createTime=\"\(iso.string(from: createTime))\" creator=\"\(esc(creator))\">\n"
        x += "  <Event>\n    <Name>\(esc(set.eventTitle.isEmpty ? "Cakra Pencil" : set.eventTitle))</Name>\n  </Event>\n"
        x += "  <RaceCourseData>\n"
        // Peta: koordinat mm dari pojok kiri bawah area peta, sumbu y ke atas (konvensi IOF XML 3.0).
        x += "    <Map>\n      <Scale>\(sheet.scaleDenominator)</Scale>\n"
        x += "      <MapPositionTopLeft x=\"0\" y=\"\(f(frame.heightM * mmPerM))\" unit=\"mm\"/>\n"
        x += "      <MapPositionBottomRight x=\"\(f(frame.widthM * mmPerM))\" y=\"0\" unit=\"mm\"/>\n    </Map>\n"

        for c in set.controls {
            let ll = zone.unproject(c.position)
            let type: String
            switch c.kind {
            case .start: type = "Start"
            case .control: type = "Control"
            case .finish: type = "Finish"
            }
            x += "    <Control type=\"\(type)\">\n"
            x += "      <Id>\(esc(c.iofID(in: set)))</Id>\n"
            x += "      <Position lng=\"\(f(ll.lon, 7))\" lat=\"\(f(ll.lat, 7))\"/>\n"
            x += "      <MapPosition x=\"\(f((c.position.x - e.minX) * mmPerM))\" y=\"\(f((c.position.y - e.minY) * mmPerM))\" unit=\"mm\"/>\n"
            x += "    </Control>\n"
        }

        for course in set.courses {
            let list = set.controls(of: course)
            x += "    <Course>\n      <Name>\(esc(course.name))</Name>\n"
            if course.kind == .normal { x += "      <Length>\(Int(set.length(of: course).rounded()))</Length>\n" }
            if let climb = course.climbM { x += "      <Climb>\(climb)</Climb>\n" }
            var previous: ControlPoint?
            for c in list {
                let type: String
                switch c.kind {
                case .start: type = "Start"
                case .control: type = "Control"
                case .finish: type = "Finish"
                }
                x += "      <CourseControl type=\"\(type)\">\n        <Control>\(esc(c.iofID(in: set)))</Control>\n"
                if course.kind == .normal, let p = previous {
                    x += "        <LegLength>\(Int(p.position.distance(to: c.position).rounded()))</LegLength>\n"
                }
                x += "      </CourseControl>\n"
                previous = c
            }
            if course.competitors > 0 { x += "      <NumberOfCompetitors>\(course.competitors)</NumberOfCompetitors>\n" }
            x += "    </Course>\n"
        }
        x += "  </RaceCourseData>\n</CourseData>\n"
        return Data(x.utf8)
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
