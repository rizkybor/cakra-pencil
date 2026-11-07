import CakraCore
import XCTest

/// OCAD 10 files (572-byte symbol header with a ShortString name, 40-byte object header) and OCAD course setting data
/// (control strings type 1 linked to their objects, course strings type 2).
final class Ocad10CourseTests: XCTestCase {
    /// Minimal OCAD 10 file: line symbol 101.0, course symbols 701/702/706, one contour line, and optionally a
    /// course setting with start S1, controls 31 and 32, finish F1, and course "A" = S1 32 31 F1.
    static func makeOcad10(withCourses: Bool) -> Data {
        var d = Data(count: 64)
        func put<T: FixedWidthInteger>(_ v: T, at o: Int) {
            if d.count < o + MemoryLayout<T>.size { d.count = o + MemoryLayout<T>.size }
            withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(o ..< o + MemoryLayout<T>.size, with: $0) }
        }
        func append(_ bytes: Data) -> Int { let o = d.count; d.append(bytes); return o }
        put(UInt16(0x0CAD), at: 0)
        put(Int16(10), at: 4)

        // Symbols (TBaseSym 572 bytes; type data from +572).
        let symBlock = append(Data(count: 4 + 256 * 4))
        func symbol(_ number: Int32, kind: UInt8, name: String, size: Int32) -> Int {
            let sp = append(Data(count: Int(size)))
            put(size, at: sp)
            put(number, at: sp + 4)
            put(kind, at: sp + 8)
            put(Int16(5), at: sp + 28)
            put(UInt8(name.utf8.count), at: sp + 56)
            for (i, b) in name.utf8.enumerated() { put(b, at: sp + 57 + i) }
            return sp
        }
        let contour = symbol(101_000, kind: 2, name: "Contour", size: 648)
        put(Int16(5), at: contour + 572)   // line color
        put(Int16(21), at: contour + 574)  // 0.21 mm
        var symbols = [contour]
        for (n, name) in [(Int32(701_000), "Start"), (702_000, "Control point"), (706_000, "Finish")] {
            symbols.append(symbol(n, kind: 1, name: name, size: 600))
        }
        for (i, sp) in symbols.enumerated() { put(UInt32(sp), at: symBlock + 4 + i * 4) }
        put(UInt32(symBlock), at: 8)

        // Objects (TElement header 40 bytes, nItem at +8). Paper mm × 100 << 8.
        let objBlock = append(Data(count: 4 + 256 * 40))
        var objects: [(sym: Int32, kind: UInt8, pts: [(Int32, Int32)])] = [(101_000, 2, [(0, 0), (1000, 0), (2000, 1000)])]
        if withCourses {
            objects += [(701_000, 1, [(0, 0)]), (702_000, 1, [(1000, 0)]), (702_000, 1, [(2000, 1000)]), (706_000, 1, [(100, 100)])]
        }
        for (i, o) in objects.enumerated() {
            let pos = append(Data(count: 40 + o.pts.count * 8))
            put(o.sym, at: pos)
            put(o.kind, at: pos + 4)
            put(Int32(o.pts.count), at: pos + 8)
            for (k, p) in o.pts.enumerated() {
                put(p.0 << 8, at: pos + 40 + k * 8)
                put(p.1 << 8, at: pos + 44 + k * 8)
            }
            let e = objBlock + 4 + i * 40
            put(UInt32(pos), at: e + 16)
            put(UInt32(40 + o.pts.count * 8), at: e + 20)
            put(o.sym, at: e + 24)
            put(o.kind, at: e + 28)
            put(UInt8(1), at: e + 30)  // status normal
        }
        put(UInt32(objBlock), at: 12)

        // Strings: scale/georeference, color, and the course setting (object index is 1-based).
        let strBlock = append(Data(count: 4 + 256 * 16))
        var strings: [(String, Int32, Int32)] = [("\tm10000\tg100\tr1\tx680000\ty9304000\ta0", 1039, 0), ("Brown\tn5\tc0\tm56\ty100\tk18", 9, 0)]
        if withCourses {
            strings += [("S1\tYs", 1, 2), ("31\tYc\td5.11", 1, 3), ("32\tYc", 1, 4), ("F1\tYf", 1, 5),
                        ("A\tsS1\tc32\tc31\tfF1", 2, 0), ("B\tsS1\tc31\tc99\tfF1", 2, 0)]
        }
        for (i, (text, type, obj)) in strings.enumerated() {
            let bytes = Data(text.utf8) + Data([0])
            let pos = append(bytes)
            let e = strBlock + 4 + i * 16
            put(UInt32(pos), at: e)
            put(UInt32(bytes.count), at: e + 4)
            put(type, at: e + 8)
            put(obj, at: e + 12)
        }
        put(UInt32(strBlock), at: 32)
        return d
    }

    func testReadsOcad10SymbolsAndObjects() throws {
        let map = try OcadReader.read(Self.makeOcad10(withCourses: false))
        XCTAssertEqual(map.version, 10)
        XCTAssertEqual(map.symbols[101_000]?.name, "Contour", "ShortString symbol name")
        XCTAssertEqual(map.symbols[101_000]?.lineWidthMM, 0.21, "Line data read 224 bytes earlier than OCAD 11")
        let (features, report) = try map.features()
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(features.first?.nodes.count, 3)
        // (10 mm, 0) on paper at 1:10000 = 100 m east of the offset.
        XCTAssertEqual(features.first?.nodes[1].point.x ?? 0, 680_100, accuracy: 1e-6)
    }

    func testReadsCourseSetting() throws {
        let c = try OcadReader.courses(Self.makeOcad10(withCourses: true))
        XCTAssertEqual(c.controls.map(\.kind), [.start, .control, .control, .finish])
        XCTAssertEqual(c.controls.compactMap(\.code), [31, 32])
        XCTAssertEqual(c.controls[2].position.x, 680_200, accuracy: 1e-6)
        XCTAssertEqual(c.controls[2].position.y, 9_304_100, accuracy: 1e-6)
        XCTAssertEqual(c.skippedDescriptions, 1, "OCAD description numbering is not converted")
        let a = try XCTUnwrap(c.courses.first { $0.name == "A" })
        let order = a.controlIDs.compactMap { id in c.controls.first { $0.id == id } }.map { $0.code.map(String.init) ?? $0.kind.rawValue }
        XCTAssertEqual(order, ["start", "32", "31", "finish"])
        XCTAssertEqual(c.missingReferences, 1, "Course B refers to control 99, which is not in the file")
    }

    func testMapWithoutCourseSettingHasNoControls() throws {
        XCTAssertTrue(try OcadReader.courses(Self.makeOcad10(withCourses: false)).controls.isEmpty)
    }
}
