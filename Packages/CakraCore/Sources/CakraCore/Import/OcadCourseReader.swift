import Foundation

/// Courses from an OCAD course setting file (.ocd, versions 10–2018), based on the OCAD file format documentation:
///
/// - Control parameter strings (type 1): "<code>\tY<type>…", type s = start, c = control, f = finish. The string index
///   links each control to its object, whose first point is the control position.
/// - Course parameter strings (type 2): "<name>\ts<start>\tc<code>…\tf<finish>" in course order.
///
/// Control descriptions use OCAD's own numbering and are not converted (reported in `skippedDescriptions`);
/// the course symbols themselves (701–799) are not imported as map objects.
public struct OcadCourseImport: Sendable {
    public var controls: [ControlPoint]
    public var courses: [Course]
    /// Controls that had OCAD description columns (re-enter them in the Descriptions tab).
    public var skippedDescriptions: Int
    /// Course entries referring to controls that are not in the file.
    public var missingReferences: Int
}

extension OcadReader {
    /// Read the course setting part of an OCAD file; empty `controls` when the file has no course setting data.
    public static func courses(_ data: Data) throws -> OcadCourseImport {
        let map = try read(data)
        guard let offset = map.realWorldOffset else { throw OcadReadError.notGeoreferenced }
        let r = Bytes(data)
        let a = map.gridAngleDeg * .pi / 180
        let (ca, sa) = (cos(a), sin(a))
        func world(_ x: Double, _ y: Double) -> Point2D {
            let mx = x / 1000 * map.scale, my = y / 1000 * map.scale
            return Point2D(x: offset.x + mx * ca - my * sa, y: offset.y + mx * sa + my * ca)
        }

        // Object positions by 1-based object index (as used in the string index). Point objects only need
        // their first coordinate, right after the TElement header.
        let version = map.version
        let elementHeader = version >= 11 ? 56 : 40
        var objectPositions: [Int: Point2D] = [:]
        var index = 0
        try walk(blocks: Int(try r.u32(12)), r: r, entrySize: 40) { o in
            index += 1
            let pos = Int(try r.u32(o + 16))
            guard pos > 0 else { return }
            let rx = try r.i32(pos + elementHeader), ry = try r.i32(pos + elementHeader + 4)
            objectPositions[index] = world(Double(rx >> 8) / 100, Double(ry >> 8) / 100)
        }

        var controlStrings: [(text: String, object: Int)] = []
        var courseStrings: [String] = []
        try walk(blocks: Int(try r.u32(32)), r: r, entrySize: 16) { o in
            let pos = Int(try r.u32(o)), len = Int(try r.u32(o + 4)), type = try r.i32(o + 8), obj = Int(try r.i32(o + 12))
            guard pos > 0, len > 0 else { return }
            if type == 1 { controlStrings.append((try r.string(pos, len), obj)) }
            if type == 2 { courseStrings.append(try r.string(pos, len)) }
        }

        var controls: [ControlPoint] = []
        var byCode: [String: UUID] = [:]
        var described = 0
        for (text, object) in controlStrings {
            let name = text.components(separatedBy: "\t").first?.trimmingCharacters(in: .whitespaces) ?? ""
            let par = parseParams(text)
            let kind: ControlKind
            switch par["Y"] {
            case "s": kind = .start
            case "c": kind = .control
            case "f": kind = .finish
            default: continue // marked route, crossing point, … not supported yet
            }
            guard !name.isEmpty, byCode[name] == nil, let position = objectPositions[object] else { continue }
            let code = kind == .control ? Int(name) : nil
            let c = ControlPoint(kind: kind, code: code, position: position)
            if ["c", "d", "e", "f", "g", "h"].contains(where: { par[$0] != nil }) { described += 1 }
            controls.append(c)
            byCode[name] = c.id
        }

        var courses: [Course] = []
        var missing = 0
        for text in courseStrings {
            let parts = text.components(separatedBy: "\t")
            let name = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            var ids: [UUID] = []
            for part in parts.dropFirst() {
                guard let key = part.first, "scf".contains(key) else { continue }
                let ref = String(part.dropFirst())
                if let id = byCode[ref] { ids.append(id) } else { missing += 1 }
            }
            guard !name.isEmpty, !ids.isEmpty else { continue }
            courses.append(Course(name: name, controlIDs: ids))
        }
        return OcadCourseImport(controls: controls, courses: courses, skippedDescriptions: described, missingReferences: missing)
    }
}
