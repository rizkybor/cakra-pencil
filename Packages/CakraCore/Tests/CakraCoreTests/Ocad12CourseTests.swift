import CakraCore
import XCTest

/// OCAD 12+ course setting files keep each control's string in the control object itself ("object string"), not in
/// the string index; the code is parameter `a`.
final class Ocad12CourseTests: XCTestCase {
    static func makeOcad12Courses() -> Data {
        var d = Data(count: 64)
        func put<T: FixedWidthInteger>(_ v: T, at o: Int) {
            if d.count < o + MemoryLayout<T>.size { d.count = o + MemoryLayout<T>.size }
            withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(o ..< o + MemoryLayout<T>.size, with: $0) }
        }
        func append(_ bytes: Data) -> Int { let o = d.count; d.append(bytes); return o }
        put(UInt16(0x0CAD), at: 0)
        put(UInt8(1), at: 2)       // file type: course setting
        put(Int16(12), at: 4)

        let symBlock = append(Data(count: 4 + 256 * 4))
        for (i, (n, name)) in [(Int32(701_000), "Start"), (702_000, "Control point"), (706_000, "Finish")].enumerated() {
            let sp = append(Data(count: 820))
            put(Int32(820), at: sp)
            put(n, at: sp + 4)
            put(UInt8(1), at: sp + 8)
            for (k, u) in name.utf16.enumerated() { put(u, at: sp + 56 + k * 2) }
            put(UInt32(sp), at: symBlock + 4 + i * 4)
        }
        put(UInt32(symBlock), at: 8)

        // Objects: 56-byte TElement header; object string (UTF-16, padded to 8 bytes) after the coordinates.
        let objBlock = append(Data(count: 4 + 256 * 40))
        let objects: [(Int32, (Int32, Int32), String)] = [
            (701_000, (0, 0), "00S1\tYs\taS1"),
            (702_000, (1000, 0), "1031\tYc\ta31\td5.011"),
            (702_000, (2000, 1000), "1032\tYc\ta32"),
            (706_000, (100, 100), "30F1\tYf\taF1"),
        ]
        for (i, (sym, p, text)) in objects.enumerated() {
            var units = Array(text.utf16)
            while units.count % 4 != 0 { units.append(0) }
            let nString = units.count / 4
            let pos = append(Data(count: 56 + 8 + nString * 8))
            put(sym, at: pos)
            put(UInt8(1), at: pos + 4)
            put(Int32(1), at: pos + 44)            // nItem
            put(Int16(0), at: pos + 48)            // nText
            put(Int16(nString), at: pos + 50)      // nObjectString (8-byte units)
            put(UInt8(1), at: pos + 54)            // ObjectStringType: control
            put(p.0 << 8, at: pos + 56)
            put(p.1 << 8, at: pos + 60)
            for (k, u) in units.enumerated() { put(u, at: pos + 64 + k * 2) }
            let e = objBlock + 4 + i * 40
            put(UInt32(pos), at: e + 16)
            put(sym, at: e + 24)
            put(UInt8(1), at: e + 28)
            put(UInt8(1), at: e + 30)
        }
        put(UInt32(objBlock), at: 12)

        let strBlock = append(Data(count: 4 + 256 * 16))
        let strings: [(String, Int32)] = [("\tm4000\tg100\tr1\tx694000\ty9311000\ta0", 1039), ("Purple\tn11\tc0\tm100\ty0\tk0", 9),
                                         ("Men\tmM2\tsS1\tc32\tc31\tmM1\tfF1\tE1.10", 2)]
        for (i, (text, type)) in strings.enumerated() {
            let bytes = Data(text.utf8) + Data([0])
            let pos = append(bytes)
            put(UInt32(pos), at: strBlock + 4 + i * 16)
            put(UInt32(bytes.count), at: strBlock + 8 + i * 16)
            put(type, at: strBlock + 12 + i * 16)
        }
        put(UInt32(strBlock), at: 32)
        return d
    }

    func testControlsFromObjectStringsAndCourseOrder() throws {
        let c = try OcadReader.courses(Self.makeOcad12Courses())
        XCTAssertEqual(c.controls.map(\.kind), [.start, .control, .control, .finish])
        XCTAssertEqual(c.controls.compactMap(\.code), [31, 32], "Code from parameter a, not OCAD's sort key (1031)")
        // (10 mm, 0) on paper at 1:4000 = 40 m east of the offset.
        XCTAssertEqual(c.controls[1].position.x, 694_040, accuracy: 1e-6)
        let men = try XCTUnwrap(c.courses.first)
        XCTAssertEqual(men.name, "Men")
        let order = men.controlIDs.compactMap { id in c.controls.first { $0.id == id } }.map { $0.code.map(String.init) ?? $0.kind.rawValue }
        XCTAssertEqual(order, ["start", "32", "31", "finish"], "Map exchange (m) and extra (E) entries are skipped")
        XCTAssertEqual(c.missingReferences, 0)
    }
}
