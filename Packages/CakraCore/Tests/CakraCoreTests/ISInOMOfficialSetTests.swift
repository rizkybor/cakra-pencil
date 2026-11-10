@testable import CakraCore
import XCTest

/// OCCA's ISInOM 6.7.3 set compared with the official OCAD sets "Indoor Symbols - ISInOM - 6.7.3.ocd" and
/// "Indoor Course Setting - 6.7.3.ocd" (in `internal/`, not in git: skipped when the files are missing).
///
/// Codes: OCAD numbers the sub-symbols .100 / .200 / .400 where the specification writes .1 / .2 / .4.
final class ISInOMOfficialSetTests: XCTestCase {
    private let internalDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../internal").standardized

    private func load(_ file: String) throws -> OcadMap {
        let url = internalDir.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("\(file) not available") }
        return try OcadReader.read(Data(contentsOf: url))
    }

    /// OCCA (specification) code → official OCAD code where the rule ".n" → ".n00" doesn't apply.
    static let codeOverrides = ["301.0": "301.100", "302.0": "302.100", "301.1": "301.500", "520.0": "520.1"]

    /// Names OCCA takes from the specification text where the OCAD set words them differently.
    static let specNames: Set<String> = [
        "521.0", "1103.1", "1103.3", "1104.0", "1108.0", "1201.1", "1204.0", "1210.0", "1211.0", "1214.0", "1215.0", "1216.0",
        "1221.0", "1703.0", "512.2", "512.3", "1775.0", "709.0", "714.0", "714.1", "301.0", "302.0", "520.0", "301.1", "709.4",
    ]

    /// Sizes OCCA takes from the specification (or approximates) where the OCAD set differs — see the report in
    /// `OccaISInOMSymbols.swift` and the README.
    static let sizeExceptions: Set<String> = [
        "512.1",   // (fig.) triangles drawn as half dots; OCAD has no main line
        "1216.0", "1771.2", // (fig.) chevrons drawn as ticks
        "701.0",   // start: side 7.0 on the centre line (OCAD 6.48 on the centre line ≈ 7.0 outside)
        "702.0",   // map issue point: 0.48 × 2.0 (spec figure); OCAD 0.6 × 2.5
        "1703.0",  // centre dot ø0.6 (spec, course set); symbol set ø0.4
        "709.4",   // 0.4 (spec, course set); symbol set 0.34
    ]

    private func ocdCode(_ code: String, in ocd: [String: MapSymbol]) -> String {
        if let o = Self.codeOverrides[code] { return o }
        let p = code.split(separator: ".")
        if p.count == 2, p[1] != "0", let n = Int(p[1]), n < 10, ocd["\(p[0]).\(n * 100)"] != nil { return "\(p[0]).\(n * 100)" }
        return code
    }

    private func norm(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Outside-measure size of a point symbol, white masks / halos excluded.
    private func bbox(_ e: [PointElement]) -> (Double, Double) {
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for el in e where el.colorHex != "#FFFFFF" {
            let r: Double
            switch el.kind {
            case .dot: r = el.diameterMM / 2
            case .circle: r = el.diameterMM / 2 + el.lineWidthMM / 2
            case .line: r = el.lineWidthMM / 2
            case .area: r = 0
            }
            for p in el.points { minX = min(minX, p.x - r); maxX = max(maxX, p.x + r); minY = min(minY, p.y - r); maxY = max(maxY, p.y + r) }
        }
        return (maxX - minX, maxY - minY)
    }

    private func channelsClose(_ a: String, _ b: String) -> Bool {
        func rgb(_ h: String) -> [Int] {
            let v = Int(h.dropFirst(), radix: 16) ?? 0
            return [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]
        }
        return zip(rgb(a), rgb(b)).allSatisfy { abs($0 - $1) <= 1 }
    }

    func testMatchesOfficialSymbolSet() throws {
        let map = try load("Indoor Symbols - ISInOM - 6.7.3.ocd")
        let course = try load("Indoor Course Setting - 6.7.3.ocd")
        XCTAssertEqual(map.scale, 700)
        let official = Dictionary(map.symbolSet(name: "ISInOM", sourceFile: "x.ocd").symbols.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let officialCourse = Dictionary(course.symbolSet(name: "Course", sourceFile: "y.ocd").symbols.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let occa = OccaStandardSymbols.isinomFile()
        var report: [String] = []
        var pairs: [(MapSymbol, MapSymbol)] = []
        for s in occa.symbols {
            // Course symbols: the course setting set (its purples); others: the map symbol set.
            let isCourse = (700_000..<800_000).contains(s.number) || s.code == "1703.0"
            let table = isCourse ? officialCourse : official
            let code = ocdCode(s.code, in: table)
            guard let o = table[code] ?? official[ocdCode(s.code, in: official)] else {
                XCTFail("\(s.code) \(s.name): not in the official set"); continue
            }
            pairs.append((s, o))
            XCTAssertEqual(s.kind, o.kind, "\(s.code) kind")
            if norm(s.name) != norm(o.name) {
                report.append("name \(s.code) '\(s.name)' ↔ \(code) '\(o.name)'")
                XCTAssertTrue(Self.specNames.contains(s.code), "\(s.code) name '\(s.name)' ≠ OCAD '\(o.name)'")
            }
            guard !Self.sizeExceptions.contains(s.code) else { continue }
            switch s.kind {
            case .line:
                let a = s.lineStyle, b = o.lineStyle
                if let b {
                    XCTAssertEqual(a?.widthMM ?? 0, b.widthMM, accuracy: 0.011, "\(s.code) line width")
                    XCTAssertTrue(channelsClose(s.colorHex, b.colorHex), "\(s.code) color \(s.colorHex) ≠ \(b.colorHex)")
                    if let d = b.dashMM { XCTAssertEqual(a?.dashMM ?? [], d, "\(s.code) dash") }
                } else {
                    // OCAD line made only of repeated symbols (1106 dotted curtain).
                    report.append("line \(s.code): OCAD has no main line (symbols only)")
                }
            case .point:
                let (w, h) = bbox(s.pointElements ?? []), (ow, oh) = bbox(o.pointElements ?? [])
                XCTAssertEqual(w, ow, accuracy: 0.05, "\(s.code) \(s.name) width OM")
                XCTAssertEqual(h, oh, accuracy: 0.05, "\(s.code) \(s.name) height OM")
            case .area:
                if let p = s.patterns, !p.isEmpty {
                    let op = o.patterns ?? []
                    XCTAssertEqual(p.count, s.code == "709.0" ? 2 : op.count, "\(s.code) patterns")
                    for (x, y) in zip(p, op) {
                        XCTAssertEqual(x.sizeMM, y.sizeMM, accuracy: 0.011, "\(s.code) pattern size")
                        if s.code != "709.0" { XCTAssertEqual(x.spacingMM, y.spacingMM, accuracy: 0.011, "\(s.code) pattern spacing") }
                        XCTAssertTrue(channelsClose(x.colorHex, y.colorHex), "\(s.code) pattern color")
                    }
                }
                if !SymbolOrnaments.isPatternOnly(fillHex: s.colorHex, patterns: s.patterns) {
                    XCTAssertTrue(channelsClose(s.colorHex, o.colorHex), "\(s.code) fill \(s.colorHex) ≠ \(o.colorHex)")
                }
            case .text:
                XCTAssertTrue(channelsClose(s.colorHex, o.colorHex), "\(s.code) text color")
            }
        }
        // Color order: OCCA's color table follows the official order (§4.3); every symbol pair layers the same way.
        let order = occa.colors.compactMap { Int($0.id.dropFirst()) }.map { map.colorOrder[$0] ?? -1 }
        XCTAssertFalse(order.contains(-1), "All colors exist in the official table")
        XCTAssertEqual(order, order.sorted(), "Color order as in the official set")
        let mapPairs = pairs.filter { !(700_000..<800_000).contains($0.0.number) && $0.0.code != "1703.0" }
        for (i, a) in mapPairs.enumerated() {
            for b in mapPairs[(i + 1)...] {
                guard let pa = a.0.colorPriority, let pb = b.0.colorPriority, let qa = a.1.colorPriority, let qb = b.1.colorPriority,
                      qa != qb, pa != pb else { continue }
                XCTAssertEqual(pa < pb, qa < qb, "Layering \(a.0.code) / \(b.0.code)")
            }
        }
        // Official symbols OCCA leaves out (helpers and combined area + outline symbols).
        let used = Set(pairs.map(\.1.code))
        let omitted = official.keys.filter { !used.contains($0) }.sorted { (official[$0]?.number ?? 0) < (official[$1]?.number ?? 0) }
        report.append("omitted from the OCAD set: " + omitted.map { "\($0) \(official[$0]!.name)" }.joined(separator: "; "))
        print("ISInOM vs official OCAD set:\n" + report.joined(separator: "\n"))
    }
}
