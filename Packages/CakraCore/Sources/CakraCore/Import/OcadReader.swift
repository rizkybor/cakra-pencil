import Foundation

/// Pembaca file OCAD (.ocd) versi 11–2018 untuk objek garis dan area, berdasarkan dokumentasi format file
/// yang dipublikasikan OCAD AG. Yang dibaca: georeferensi (string 1039), tabel warna (string 9), simbol
/// (nomor, nama, warna, tebal garis), dan objek berstatus normal.
///
/// Yang dilewati (dilaporkan di `OcadImportReport`): objek titik, teks, lubang di area (hanya ring luar),
/// dan objek yang dihapus/tersembunyi di OCAD.
///
/// Semua pembacaan dicek batasnya: file rusak menghasilkan error, bukan crash.
public struct OcadMap: Sendable {
    public struct Symbol: Sendable {
        public var number: Int        // ×1000, mis. 101000 = 101.0
        public var kind: UInt8        // 1 titik, 2 garis, 3 area, 4 teks, 5 teks garis, 6 teks garis, 7 persegi
        public var name: String
        public var colorNumber: Int
        public var lineWidthMM: Double?
        /// Garis ganda (jalan, setapak, rel): lebar antar tepi, tebal tepi, warna isi (nil = tanpa isi) dan tepi.
        var doubleLine: (widthMM: Double, edgeWidthMM: Double, fillColor: Int?, edgeColor: Int)?
        /// TLineSym: LineStyle (0 rata, 1 bulat, 2 tajam), MainLength/MainGap dan DblLength/DblGap (mm).
        var lineCapStyle = 1
        var dash: (length: Double, gap: Double)?
        var doubleDash: (length: Double, gap: Double)?
        /// Elemen simbol titik mentah (nomor warna belum diubah ke hex); lihat `pointElements(of:)`.
        var rawPointElements: [(kind: Int, color: Int, lw: Double, diam: Double, pts: [Point2D])] = []

        /// Kode seperti di OCAD: 101000 → "101.0", 503001 → "503.1".
        public var code: String { "\(number / 1000).\(number % 1000)" }
    }

    public struct Object: Sendable {
        public var symbol: Int
        public var kind: UInt8
        /// Koordinat kertas dalam mm (sumbu y ke atas) + flag OCAD.
        public var points: [(x: Double, y: Double, xFlags: UInt8, yFlags: UInt8)]
    }

    public var version: Int
    public var scale: Double
    /// Offset dunia nyata (m) dan rotasi grid (derajat) dari parameter skala; nil bila peta tidak ter-georeferensi.
    public var realWorldOffset: Point2D?
    public var gridAngleDeg: Double
    public var symbols: [Int: Symbol]
    /// Warna CMYK → hex sRGB per nomor warna OCAD.
    public var colors: [Int: String]
    /// Urutan warna di tabel warna (prioritas gambar; 0 = paling atas).
    public var colorOrder: [Int: Int] = [:]
    public var objects: [Object]
}

public struct OcadImportReport: Sendable {
    public var imported = 0
    public var skippedPoints = 0
    public var skippedText = 0
    public var droppedHoles = 0
}

public enum OcadReadError: Error, LocalizedError, Equatable {
    case notOcad
    case unsupportedVersion(Int)
    case corrupt(String)
    case notGeoreferenced

    public var errorDescription: String? {
        switch self {
        case .notOcad: return "Bukan file OCAD (.ocd)."
        case let .unsupportedVersion(v): return "OCAD versi \(v) belum didukung. Simpan ulang di OCAD 11 atau lebih baru."
        case let .corrupt(what): return "File OCAD rusak: \(what)."
        case .notGeoreferenced: return "Peta OCAD ini belum ter-georeferensi (koordinat dunia nyata mati), jadi posisinya tidak bisa ditentukan."
        }
    }
}

public enum OcadReader {
    // Flag koordinat OCAD (8 bit bawah tiap int32).
    static let xFirstBezier: UInt8 = 1
    static let xSecondBezier: UInt8 = 2
    static let yHoleStart: UInt8 = 2

    static let maxBlocks = 4096

    public static func read(_ data: Data) throws -> OcadMap {
        let r = Bytes(data)
        guard data.count >= 48, try r.u16(0) == 0x0CAD else { throw OcadReadError.notOcad }
        let version = Int(try r.i16(4))
        guard (11...2018).contains(version) else { throw OcadReadError.unsupportedVersion(version) }

        let symbolBlock = Int(try r.u32(8))
        let objectBlock = Int(try r.u32(12))
        let stringBlock = Int(try r.u32(32))

        // String parameter: warna (9) dan skala/georeferensi (1039).
        var colors: [Int: String] = [:]
        var colorOrder: [Int: Int] = [:]
        var scalePar: String?
        try walk(blocks: stringBlock, r: r, entrySize: 16) { o in
            let pos = Int(try r.u32(o)), len = Int(try r.u32(o + 4)), type = try r.i32(o + 8)
            guard pos > 0, len > 0, type == 9 || type == 1039 else { return }
            let text = try r.string(pos, len)
            if type == 1039 {
                scalePar = text
            } else if let (n, hex) = parseColor(text) {
                colors[n] = hex
                colorOrder[n] = colorOrder.count
            }
        }
        let par = parseParams(scalePar ?? "")
        let scale = Double(par["m"] ?? "") ?? 0
        guard scale > 0 else { throw OcadReadError.corrupt("skala peta tidak ada") }
        var offset: Point2D?
        if par["r"] == "1", let x = Double(par["x"] ?? ""), let y = Double(par["y"] ?? "") {
            offset = Point2D(x: x, y: y)
        }

        // Simbol: TBaseSym → nomor (4), jenis (8), warna pertama (28), nama UTF-16 64 karakter (56).
        // Simbol garis: warna garis (796) dan tebal garis 0,01 mm (798).
        var symbols: [Int: OcadMap.Symbol] = [:]
        try walk(blocks: symbolBlock, r: r, entrySize: 4) { o in
            let sp = Int(try r.u32(o))
            guard sp > 0 else { return }
            let size = Int(try r.i32(sp))
            guard size >= 184 else { throw OcadReadError.corrupt("simbol terlalu pendek") }
            let number = Int(try r.i32(sp + 4))
            let kind = try r.u8(sp + 8)
            var color = Int(try r.i16(sp + 28))
            let name = try r.utf16(sp + 56, maxChars: 64)
            var width: Double?
            var double: (widthMM: Double, edgeWidthMM: Double, fillColor: Int?, edgeColor: Int)?
            if kind == 2, size >= 840 {
                let lineColor = Int(try r.i16(sp + 796)), lw = Int(try r.i16(sp + 798))
                if lw > 0 {
                    width = Double(lw) / 100
                    color = lineColor
                }
                // TLineSym: DblMode 822, DblFlags 824 (bit 1 = isi), DblFillColor 826, DblLeftColor 828,
                // DblWidth 832, DblLeftWidth 834, DblRightWidth 836 (0,01 mm).
                let dblMode = Int(try r.i16(sp + 822)), dblFlags = Int(try r.i16(sp + 824))
                let dblWidth = Int(try r.i16(sp + 832))
                let edge = (Int(try r.i16(sp + 834)) + Int(try r.i16(sp + 836))) / 2
                if lw == 0, dblMode != 0, dblWidth > 0 {
                    double = (Double(dblWidth) / 100, Double(edge) / 100,
                              dblFlags & 1 != 0 ? Int(try r.i16(sp + 826)) : nil, Int(try r.i16(sp + 828)))
                }
            }
            var elements: [(kind: Int, color: Int, lw: Double, diam: Double, pts: [Point2D])] = []
            if kind == 1, size >= 800 {
                // TPointSym: DataSize (jumlah TCord) di 796, elemen mulai 800. Tiap elemen: header 16 byte
                // (jenis, flag, warna, tebal, diameter, jumlah titik) lalu titik-titiknya.
                let dataSize = Int(try r.u16(sp + 796))
                var o = sp + 800
                let end = min(o + dataSize * 8, sp + size)
                while o + 16 <= end {
                    let type = Int(try r.i16(o)), col = Int(try r.i16(o + 4))
                    let lw = Double(try r.i16(o + 6)) / 100, diam = Double(try r.i16(o + 8)) / 100
                    let n = Int(try r.i16(o + 10))
                    guard (1...4).contains(type), (0...10_000).contains(n), o + 16 + n * 8 <= end else { break }
                    var pts: [Point2D] = []
                    for k in 0..<n {
                        let x = try r.i32(o + 16 + k * 8), y = try r.i32(o + 20 + k * 8)
                        pts.append(Point2D(x: Double(x >> 8) / 100, y: Double(y >> 8) / 100))
                    }
                    elements.append((type, col, lw, diam, pts))
                    o += 16 + n * 8
                }
            }
            var sym = OcadMap.Symbol(number: number, kind: kind, name: name, colorNumber: color, lineWidthMM: width)
            sym.rawPointElements = elements
            sym.doubleLine = double
            if kind == 2, size >= 842 {
                sym.lineCapStyle = Int(try r.i16(sp + 800))
                let main = Int(try r.i16(sp + 806)), gap = Int(try r.i16(sp + 810))
                if main > 0, gap > 0 { sym.dash = (Double(main) / 100, Double(gap) / 100) }
                let dblLength = Int(try r.i16(sp + 838)), dblGap = Int(try r.i16(sp + 840))
                if double != nil, dblLength > 0, dblGap > 0 { sym.doubleDash = (Double(dblLength) / 100, Double(dblGap) / 100) }
            }
            symbols[number] = sym
        }

        // Objek: TObjectIndex 40 byte → posisi, simbol, jenis, status (1 = normal).
        // TElement: header 56 byte, nItem di +44, koordinat TCord (2 × int32) mulai +56.
        var objects: [OcadMap.Object] = []
        try walk(blocks: objectBlock, r: r, entrySize: 40) { o in
            let pos = Int(try r.u32(o + 16))
            let status = try r.u8(o + 30)
            guard pos > 0, status == 1 else { return }
            let sym = Int(try r.i32(pos)), kind = try r.u8(pos + 4)
            let n = Int(try r.u32(pos + 44))
            guard n <= 1_000_000 else { throw OcadReadError.corrupt("jumlah titik objek tidak masuk akal") }
            var pts: [(x: Double, y: Double, xFlags: UInt8, yFlags: UInt8)] = []
            pts.reserveCapacity(n)
            for k in 0..<n {
                let rx = try r.i32(pos + 56 + k * 8), ry = try r.i32(pos + 60 + k * 8)
                pts.append((Double(rx >> 8) / 100, Double(ry >> 8) / 100, UInt8(truncatingIfNeeded: rx), UInt8(truncatingIfNeeded: ry)))
            }
            objects.append(OcadMap.Object(symbol: sym, kind: kind, points: pts))
        }

        return OcadMap(version: version, scale: scale, realWorldOffset: offset, gridAngleDeg: Double(par["a"] ?? "") ?? 0,
                       symbols: symbols, colors: colors, colorOrder: colorOrder, objects: objects)
    }

    /// Ikuti rantai blok index (4 byte pointer blok berikutnya + 256 entri). Melindungi dari blok melingkar.
    static func walk(blocks first: Int, r: Bytes, entrySize: Int, _ body: (Int) throws -> Void) throws {
        var pos = first
        var seen = Set<Int>()
        while pos > 0 {
            guard seen.insert(pos).inserted, seen.count <= maxBlocks else { throw OcadReadError.corrupt("rantai index melingkar") }
            let next = Int(try r.u32(pos))
            for i in 0..<256 { try body(pos + 4 + i * entrySize) }
            pos = next
        }
    }

    /// "Nama\tn152\tc0\tm60\ty90\tk20..." → (152, "#RRGGBB").
    static func parseColor(_ s: String) -> (Int, String)? {
        let p = parseParams(s)
        guard let n = Int(p["n"] ?? "") else { return nil }
        func v(_ k: String) -> Double { min(max((Double(p[k] ?? "") ?? 0) / 100, 0), 1) }
        let (c, m, y, k) = (v("c"), v("m"), v("y"), v("k"))
        let rgb = [(1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k)].map { Int(($0 * 255).rounded()) }
        return (n, String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2]))
    }

    /// Parameter OCAD: teks pertama, lalu pasangan "\t<kode 1 huruf><nilai>". Kode pertama yang muncul yang dipakai.
    static func parseParams(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        // components (bukan split): teks pertama boleh kosong, mis. "\tm10000\tx680000".
        for part in s.components(separatedBy: "\t").dropFirst() {
            guard let key = part.first else { continue }
            let k = String(key)
            if out[k] == nil { out[k] = String(part.dropFirst()) }
        }
        return out
    }
}

extension OcadMap {
    /// Gaya garis IOF dari simbol: garis tunggal, atau garis ganda (tepi + isi) dengan lebar total.
    public func lineStyle(of s: Symbol) -> LineStyle? {
        if let d = s.doubleLine {
            // Dibulatkan ke 0,01 mm (satuan file OCAD) agar 0,35 + 0,10 = 0,45 tepat.
            func mm(_ v: Double) -> Double { (v * 100).rounded() / 100 }
            return LineStyle(colorHex: d.fillColor.flatMap { colors[$0] } ?? "#FFFFFF", widthMM: mm(d.widthMM + d.edgeWidthMM),
                             casing: LineStyle.Casing(colorHex: colors[d.edgeColor] ?? "#000000", innerWidthMM: max(mm(d.widthMM - d.edgeWidthMM), 0.01)),
                             dashMM: s.doubleDash.map { [$0.length, $0.gap] }, roundCaps: s.lineCapStyle == 1)
        }
        guard let w = s.lineWidthMM else { return nil }
        return LineStyle(colorHex: colors[s.colorNumber] ?? "#000000", widthMM: w, casing: nil,
                         dashMM: s.dash.map { [$0.length, $0.gap] }, roundCaps: s.lineCapStyle == 1)
    }

    /// Elemen simbol titik dengan warna hex dan prioritas dari tabel warna file ini.
    public func pointElements(of s: Symbol) -> [PointElement] {
        s.rawPointElements.compactMap { e in
            guard let kind = PointElement.Kind(rawValue: e.kind) else { return nil }
            return PointElement(kind: kind, colorHex: colors[e.color] ?? "#000000", priority: colorOrder[e.color] ?? 0,
                                lineWidthMM: e.lw, diameterMM: e.diam, points: e.pts.isEmpty ? [Point2D(x: 0, y: 0)] : e.pts)
        }
    }

    /// Ubah objek garis/area jadi `Feature` di koordinat UTM proyek.
    /// Kertas (mm) → meter: × skala / 1000, diputar sudut grid, lalu digeser offset dunia nyata.
    public func features() throws -> (features: [Feature], report: OcadImportReport) {
        guard let offset = realWorldOffset else { throw OcadReadError.notGeoreferenced }
        let a = gridAngleDeg * .pi / 180
        let (ca, sa) = (cos(a), sin(a))
        func world(_ x: Double, _ y: Double) -> Point2D {
            let mx = x / 1000 * scale, my = y / 1000 * scale
            return Point2D(x: offset.x + mx * ca - my * sa, y: offset.y + mx * sa + my * ca)
        }

        var report = OcadImportReport()
        var out: [Feature] = []
        for obj in objects {
            switch obj.kind {
            case 2, 3, 7: break
            case 1:
                // Objek titik: simbol dengan elemen standarnya di posisi titik pertama.
                guard let sym = symbols[obj.symbol], let first = obj.points.first else { report.skippedPoints += 1; continue }
                let elements = pointElements(of: sym)
                guard !elements.isEmpty else { report.skippedPoints += 1; continue }
                out.append(Feature.point(at: world(first.x, first.y), elements: elements, name: "\(sym.code) \(sym.name)",
                                         symbolCode: sym.code, symbolName: sym.name))
                report.imported += 1
                continue
            default: report.skippedText += 1; continue
            }
            // Ring luar saja: berhenti di titik awal lubang pertama.
            var pts = obj.points
            if let hole = pts.indices.dropFirst().first(where: { pts[$0].yFlags & OcadReader.yHoleStart != 0 }) {
                pts = Array(pts[..<hole])
                report.droppedHoles += 1
            }
            let isArea = obj.kind == 3 || obj.kind == 7
            var nodes: [BezierNode] = []
            var i = 0
            while i < pts.count {
                let p = pts[i]
                if p.xFlags & OcadReader.xFirstBezier != 0, i + 2 < pts.count, !nodes.isEmpty {
                    // c1, c2, titik akhir.
                    nodes[nodes.count - 1].outHandle = world(p.x, p.y)
                    let c2 = pts[i + 1], end = pts[i + 2]
                    nodes.append(BezierNode(point: world(end.x, end.y), inHandle: world(c2.x, c2.y)))
                    i += 3
                } else {
                    nodes.append(BezierNode(point: world(p.x, p.y)))
                    i += 1
                }
            }
            // Area OCAD mengulang titik awal di akhir; Feature menutup sendiri.
            if isArea, nodes.count > 1, nodes.first!.point.distance(to: nodes.last!.point) < 1e-6 {
                let last = nodes.removeLast()
                nodes[0].inHandle = last.inHandle
            }
            guard nodes.count >= (isArea ? 3 : 2) else { continue }

            let sym = symbols[obj.symbol]
            let code = sym?.code ?? "\(obj.symbol / 1000).\(obj.symbol % 1000)"
            let style = isArea ? nil : sym.flatMap(lineStyle(of:))
            var f = Feature(name: [code, sym?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " "),
                            kind: isArea ? .area : .line,
                            colorHex: style?.colorHex ?? sym.flatMap { colors[$0.colorNumber] } ?? "#000000",
                            widthMM: style?.widthMM ?? sym?.lineWidthMM ?? 0.14,
                            nodes: nodes,
                            symbolCode: code,
                            symbolName: sym?.name)
            if let style { f.apply(style) }
            out.append(f)
            report.imported += 1
        }
        return (out, report)
    }
}

/// Pembaca byte little-endian dengan cek batas.
struct Bytes {
    let data: Data

    init(_ data: Data) { self.data = data }

    private func check(_ o: Int, _ n: Int) throws {
        guard o >= 0, n >= 0, o <= data.count - n else { throw OcadReadError.corrupt("pointer di luar file (\(o))") }
    }

    private func load<T: FixedWidthInteger>(_ o: Int, _: T.Type) throws -> T {
        try check(o, MemoryLayout<T>.size)
        return data.withUnsafeBytes { raw in
            T(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: T.self))
        }
    }

    func u8(_ o: Int) throws -> UInt8 { try load(o, UInt8.self) }
    func u16(_ o: Int) throws -> UInt16 { try load(o, UInt16.self) }
    func i16(_ o: Int) throws -> Int16 { try load(o, Int16.self) }
    func u32(_ o: Int) throws -> UInt32 { try load(o, UInt32.self) }
    func i32(_ o: Int) throws -> Int32 { try load(o, Int32.self) }

    /// String 8-bit (Latin-1/UTF-8) sampai byte nol pertama.
    func string(_ o: Int, _ len: Int) throws -> String {
        try check(o, len)
        let bytes = data[data.startIndex + o ..< data.startIndex + o + len].prefix { $0 != 0 }
        return String(data: Data(bytes), encoding: .utf8) ?? String(decoding: bytes, as: Unicode.ASCII.self)
    }

    func utf16(_ o: Int, maxChars: Int) throws -> String {
        try check(o, maxChars * 2)
        var units: [UInt16] = []
        for i in 0..<maxChars {
            let u = try u16(o + i * 2)
            if u == 0 { break }
            units.append(u)
        }
        return String(decoding: units, as: UTF16.self)
    }
}
