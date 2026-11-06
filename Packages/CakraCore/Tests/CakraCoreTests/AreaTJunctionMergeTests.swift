import XCTest
@testable import CakraCore

/// Area bersimbol sama yang bersambungan lewat sambungan T (sudut satu area di tengah sisi area lain).
final class AreaTJunctionMergeTests: XCTestCase {
    /// Data asli dua area 501.2 (proyek Taman Adiyasa): hanya berbagi satu sudut; sudut lain area kedua
    /// jatuh di tengah sisi area pertama.
    private let first = #"[{"point": {"x": 658382.8921954719, "y": 9300322.229497358}}, {"point": {"x": 658358.3103797283, "y": 9300316.65864063}}, {"point": {"x": 658359.2758371707, "y": 9300311.761290358}}, {"point": {"x": 658378.5937133954, "y": 9300316.024022847}}, {"point": {"x": 658391.8489707449, "y": 9300256.879696546}}, {"point": {"x": 658397.7179768156, "y": 9300257.912103012}}, {"point": {"x": 658383.9003314247, "y": 9300317.817660766}}, {"point": {"x": 658403.2182076564, "y": 9300322.080393244}}, {"point": {"x": 658416.4734650002, "y": 9300262.936066948}}, {"point": {"x": 658422.633884799, "y": 9300264.48350717}}, {"outHandle": {"x": 658407.2726283456, "y": 9300327.690418625}, "point": {"x": 658407.8485064515, "y": 9300325.569508033}}, {"inHandle": {"x": 658407.2246602883, "y": 9300327.70247175}, "point": {"x": 658404.670303513, "y": 9300327.169673508}}]"#
    private let second = #"[{"point": {"x": 658421.4769077596, "y": 9300269.263574257}}, {"inHandle": {"x": 658421.9018003783, "y": 9300261.940590404}, "outHandle": {"x": 658433.0853797698, "y": 9300264.60021096}, "point": {"x": 658429.7311321318, "y": 9300263.80252127}}, {"outHandle": {"x": 658452.786663977, "y": 9300269.222607441}, "point": {"x": 658443.0345094154, "y": 9300266.862020152}}, {"point": {"x": 658464.3554663971, "y": 9300269.405294055}}, {"point": {"x": 658467.4527165185, "y": 9300261.123620283}}, {"outHandle": {"x": 658461.6305225076, "y": 9300254.031809825}, "point": {"x": 658460.0566856334, "y": 9300259.593858855}}, {"inHandle": {"x": 658450.5935445206, "y": 9300255.230486685}, "outHandle": {"x": 658452.9203672495, "y": 9300245.760626318}, "point": {"x": 658452.439379075, "y": 9300247.718184492}}, {"point": {"x": 658453.4335954555, "y": 9300242.708649168}}, {"point": {"x": 658448.1742819704, "y": 9300241.554894684}}, {"point": {"x": 658442.8074910082, "y": 9300262.359808683}}, {"point": {"x": 658424.2679868006, "y": 9300258.357786767}}, {"point": {"x": 658426.573818586, "y": 9300250.292876067}}, {"point": {"x": 658420.1133014815, "y": 9300248.713275712}}, {"point": {"x": 658417.8081260342, "y": 9300257.016602773}}, {"point": {"x": 658410.8911406534, "y": 9300255.271365918}}, {"point": {"x": 658409.4118857313, "y": 9300261.044507574}}, {"point": {"x": 658422.633884799, "y": 9300264.48350717}}, {"point": {"x": 658421.4769077596, "y": 9300269.263574257}}]"#

    private func area(_ json: String) throws -> Feature {
        let nodes = try JSONDecoder().decode([BezierNode].self, from: Data(json.utf8))
        return Feature(kind: .area, colorHex: "#F2DCC6", widthMM: 0.1, nodes: nodes, symbolCode: "501.2", symbolName: "Paved area")
    }

    func testAreasJoinedAtTJunctionAreUnited() throws {
        let a = try area(first), b = try area(second)
        let r = try XCTUnwrap(a.unitingArea(b, vertexTolerance: 0.01, flattenTolerance: 0.2), "Dua area bersambungan bisa digabung")
        XCTAssertFalse(r.flattenedCurves, "Disambung lewat sisi bersama, kurva tetap")
        // Luas hasil = jumlah luas keduanya (tidak tumpang tindih).
        XCTAssertEqual(abs(r.feature.signedArea), abs(a.signedArea) + abs(b.signedArea), accuracy: 0.5)
        // Gabung otomatis (tanpa jalur poligon) juga bisa.
        XCTAssertNotNil(b.unitingArea(a, vertexTolerance: 0.01, flattenTolerance: 0.2, allowOverlap: false))
    }

    func testInsertingVertexKeepsShape() throws {
        let a = try area(first), b = try area(second)
        let a2 = a.insertingVertices(of: b, tolerance: 0.01)
        XCTAssertEqual(a2.nodes.count, a.nodes.count + 1, "Satu sudut b jatuh di sisi a")
        XCTAssertEqual(a2.signedArea, a.signedArea, accuracy: 1e-3)
    }
}
