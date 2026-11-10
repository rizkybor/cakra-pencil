import CoreGraphics
import ImageIO
import XCTest
@testable import CakraCore

/// Areas with holes: data model, cutting, splitting, merging, transforms, hit testing, import and export.
final class AreaHolesTests: XCTestCase {
    private func P(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    private func ring(_ pts: [(Double, Double)]) -> [BezierNode] { pts.map { BezierNode(point: P($0.0, $0.1)) } }

    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [BezierNode] {
        ring([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    }

    private func area(_ pts: [BezierNode], code: String = "406.0") -> Feature {
        Feature(name: "Forest", kind: .area, colorHex: "#3CB54A", widthMM: 0, nodes: pts, symbolCode: code, symbolName: "Forest")
    }

    /// 0…10 square.
    private var square: Feature { area(rect(0, 0, 10, 10)) }

    /// 0…20 square with a 5…15 hole.
    private var donut: Feature {
        var f = area(rect(0, 0, 20, 20))
        f.holes = [rect(5, 5, 15, 15)]
        f.normalizeHoles()
        return f
    }

    private func filled(_ f: Feature) -> Double { f.filledArea(tolerance: 0.0005) }

    // MARK: Model

    func testCodableRoundTripAndOldFilesWithoutHoles() throws {
        let f = donut
        let back = try JSONDecoder().decode(Feature.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
        XCTAssertEqual(back.holeRings.count, 1)
        // No holes = no key in the JSON (older files read the same, and are written the same).
        let plain = try JSONEncoder().encode(square)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("holes"))
        XCTAssertNil(try JSONDecoder().decode(Feature.self, from: plain).holes)
    }

    func testWindingConventionHolesOppositeOuter() {
        XCTAssertGreaterThan(Feature.signedArea(of: donut.nodes), 0)
        XCTAssertLessThan(Feature.signedArea(of: donut.holeRings[0]), 0, "Counterclockwise outer → clockwise hole")
        var cw = area(rect(0, 0, 20, 20).reversed())
        cw.holes = [rect(5, 5, 15, 15).reversed()]
        cw.normalizeHoles()
        XCTAssertGreaterThan(Feature.signedArea(of: cw.holeRings[0]), 0, "Clockwise outer → counterclockwise hole")
        var tiny = square
        tiny.holes = [ring([(1, 1), (2, 2)])]
        tiny.normalizeHoles()
        XCTAssertNil(tiny.holes, "Holes with fewer than 3 points are dropped")
    }

    func testContainsPointExcludesHolesAndArea() {
        let f = donut
        XCTAssertTrue(f.containsPoint(P(2, 2), tolerance: 0.01))
        XCTAssertFalse(f.containsPoint(P(10, 10), tolerance: 0.01), "Inside the hole is not inside the area")
        XCTAssertFalse(f.containsPoint(P(30, 30), tolerance: 0.01))
        XCTAssertEqual(f.holeIndex(containing: P(10, 10), tolerance: 0.01), 0)
        XCTAssertEqual(filled(f), 400 - 100, accuracy: 1e-9)
        // Hole edges count as the object's outline (snap / tap on the edge).
        XCTAssertEqual(f.distance(to: P(10, 14), tolerance: 0.01), 1, accuracy: 1e-9)
        XCTAssertEqual(f.nearestRingPosition(to: P(10, 14))?.ring, 1)
        XCTAssertEqual(f.ringFeatures.count, 2)
    }

    func testNodeToolIndicesCoverHoles() {
        var f = donut
        XCTAssertEqual(f.allNodes.count, 8)
        XCTAssertEqual(f.ringLocation(ofNode: 5)?.ring, 1)
        XCTAssertEqual(f.ringLocation(ofNode: 5)?.index, 1)
        XCTAssertEqual(f.nodeIndex(ring: 1, index: 1), 5)
        var all = f.allNodes
        all[5] = all[5].moved(by: P(1, 0))
        f.allNodes = all
        XCTAssertEqual(f.nodes.count, 4)
        XCTAssertEqual(f.holeRings[0][1].point, donut.holeRings[0][1].point + P(1, 0))
        f.convertNode(at: 6, to: .smooth)
        XCTAssertTrue(f.holeRings[0][2].isSmooth, "Converting a hole node works on the hole")
        XCTAssertFalse(f.nodes.contains(where: \.isSmooth))
        let inserted = f.insertNode(ring: 1, at: PathPosition(segment: 0, t: 0.5))
        XCTAssertEqual(inserted, 5)
        XCTAssertEqual(f.holeRings[0].count, 5)
    }

    // MARK: Transforms

    func testTransformsCarryHoles() throws {
        let f = donut
        let moved = f.moved(by: P(100, 50))
        XCTAssertEqual(moved.holeRings[0][0].point, f.holeRings[0][0].point + P(100, 50))

        var rotated = f
        rotated.setRotation(90)
        // Pivot = mean of the outer nodes (10, 10): the centered hole maps onto itself as a set of points.
        XCTAssertEqual(Set(rotated.holeRings[0].map { P(($0.point.x * 1e6).rounded() / 1e6, ($0.point.y * 1e6).rounded() / 1e6) }),
                       Set(f.holeRings[0].map(\.point)))
        var precise = area(rect(0, 0, 20, 10))
        precise.holes = [rect(2, 2, 4, 4)]
        precise.normalizeHoles()
        precise.setRotationExactly(90)
        // Pivot (10, 5); 90° clockwise: hole corner (2, 2) → (7, 13), (4, 4) → (9, 11).
        XCTAssertEqual(precise.holeRings[0].map(\.point.y).min()!, 11, accuracy: 1e-9)
        XCTAssertEqual(precise.holeRings[0].map(\.point.x).max()!, 9, accuracy: 1e-9)

        let scaled = f.scaled(by: 2, around: P(10, 10))
        XCTAssertEqual(filled(scaled), 4 * 300, accuracy: 1e-6)
        let mirrored = f.mapped { P(-$0.x, $0.y) }
        XCTAssertLessThan(Feature.signedArea(of: mirrored.nodes) * Feature.signedArea(of: mirrored.holeRings[0]), 0,
                          "After a mirror the hole still runs opposite to the outer ring")

        var reversed = f
        reversed.reverse()
        XCTAssertLessThan(Feature.signedArea(of: reversed.nodes) * Feature.signedArea(of: reversed.holeRings[0]), 0)

        // Parallel inward: the area shrinks and its hole grows.
        let inward = f.parallel(offset: 1)
        XCTAssertEqual(abs(Feature.signedArea(of: inward.nodes)), 18 * 18, accuracy: 1e-6)
        XCTAssertEqual(abs(Feature.signedArea(of: inward.holeRings[0])), 12 * 12, accuracy: 1e-6)
        // Outward: the hole shrinks; a hole offset past its size disappears.
        XCTAssertEqual(abs(Feature.signedArea(of: f.parallel(offset: -1).holeRings[0])), 8 * 8, accuracy: 1e-6)
        XCTAssertNil(f.parallel(offset: -6).holes)

        // Copies (duplicate) are plain value copies; symbol size changes keep the geometry.
        XCTAssertEqual(f.withSymbolSize(scaledBy: 1.5).holes, f.holes)
        // A line made from the area has no holes.
        var line = f
        XCTAssertTrue(line.switchSymbol(to: MapSymbol(number: 506_000, name: "Path", kind: .line, colorHex: "#000000", lineWidthMM: 0.25, isEnabled: true)))
        XCTAssertNil(line.holes)
    }

    // MARK: Area − shape

    func testRectangleInsideMakesHole() throws {
        let f = square
        let parts = try f.subtractingShape(rect(2, 2, 4, 4)).get()
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].id, f.id)
        XCTAssertEqual(parts[0].nodes.count, 4, "Outer ring unchanged")
        XCTAssertEqual(parts[0].holeRings.count, 1)
        XCTAssertEqual(filled(parts[0]), 96, accuracy: 1e-9)
        XCTAssertLessThan(Feature.signedArea(of: parts[0].holeRings[0]), 0, "Hole wound opposite to the outer ring")
    }

    func testEllipseInsideMakesCurvedHole() throws {
        let e = Feature.ellipse(corners: [P(3, 7), P(7, 7), P(7, 3), P(3, 3)], colorHex: "#000", widthMM: 0)
        let parts = try square.subtractingShape(e.nodes).get()
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].holeRings.count, 1)
        XCTAssertTrue(parts[0].holeRings[0].contains(where: \.isSmooth), "The hole keeps the ellipse curves")
        XCTAssertEqual(filled(parts[0]), 100 - .pi * 4, accuracy: 0.01)
    }

    func testSecondCutOverlappingHoleEnlargesIt() throws {
        let one = try square.subtractingShape(rect(2, 2, 4, 4)).get()[0]
        let two = try one.subtractingShape(rect(3, 3, 6, 5)).get()
        XCTAssertEqual(two.count, 1)
        XCTAssertEqual(two[0].holeRings.count, 1, "One bigger hole, not two")
        // Union of 2×2 and 3×2 overlapping 1×1: 4 + 6 − 1 = 9.
        XCTAssertEqual(filled(two[0]), 100 - 9, accuracy: 1e-6)
    }

    func testShapeCoveringHoleAbsorbsIt() throws {
        let parts = try donut.subtractingShape(rect(3, 3, 17, 17)).get()
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].holeRings.count, 1)
        XCTAssertEqual(filled(parts[0]), 400 - 14 * 14, accuracy: 1e-6)
    }

    func testShapeInsideHoleIsReported() {
        XCTAssertEqual(donut.subtractingShape(rect(7, 7, 9, 9)), .failure(.insideHole))
        XCTAssertEqual(donut.subtractingShape(rect(30, 30, 40, 40)), .failure(.noOverlap))
    }

    func testCutAcrossEdgeAndHoleOpensHole() throws {
        // A strip from outside the right edge into the hole: the hole opens up into a notch (a C shape, no hole).
        let parts = try donut.subtractingShape(rect(12, 8, 25, 12)).get()
        XCTAssertEqual(parts.count, 1)
        XCTAssertNil(parts[0].holes, "The hole merged into the outer edge")
        XCTAssertEqual(filled(parts[0]), 300 - 5 * 4, accuracy: 1e-6)
        // A strip across the whole donut: two C pieces.
        let halves = try donut.subtractingShape(rect(8, -5, 12, 25)).get()
        XCTAssertEqual(halves.count, 2)
        XCTAssertTrue(halves.allSatisfy { $0.holes == nil })
        XCTAssertEqual(halves.map(filled).reduce(0, +), 300 - 4 * 10, accuracy: 1e-6)
    }

    func testPiecesKeepTheirOwnHoles() throws {
        // Two holes, one on each side of a strip cut through the middle.
        var f = area(rect(0, 0, 30, 10))
        f.holes = [rect(2, 2, 6, 6), rect(22, 2, 26, 6)]
        f.normalizeHoles()
        let parts = try f.subtractingShape(rect(13, -5, 17, 15)).get()
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts.allSatisfy { $0.holeRings.count == 1 }, "Each piece gets the hole inside it")
        for p in parts {
            let hole = p.holeRings[0].map(\.point)
            let x = hole.map(\.x).reduce(0, +) / Double(hole.count)
            XCTAssertTrue(p.containsPoint(P(x < 15 ? 1 : 29, 1), tolerance: 0.01))
        }
    }

    func testClockwiseAreaWithHoleKeepsDirections() throws {
        var f = area(rect(0, 0, 20, 20).reversed())
        f.holes = [rect(5, 5, 15, 15)]
        f.normalizeHoles()
        let parts = try f.subtractingShape(rect(1, 1, 3, 3)).get()
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].holeRings.count, 2)
        XCTAssertLessThan(Feature.signedArea(of: parts[0].nodes), 0, "Original clockwise direction kept")
        XCTAssertTrue(parts[0].holeRings.allSatisfy { Feature.signedArea(of: $0) > 0 })
    }

    // MARK: Split along a path

    func testSplitWithHoleGivesHoleToItsPiece() throws {
        var f = area(rect(0, 0, 20, 10))
        f.holes = [rect(2, 2, 6, 6)]
        f.normalizeHoles()
        let parts = try f.splittingArea(along: [BezierNode(point: P(10, -2)), BezierNode(point: P(10, 12))]).get()
        XCTAssertEqual(parts.count, 2)
        let left = try XCTUnwrap(parts.first { $0.nodes.map(\.point.x).min()! < 1 })
        let right = try XCTUnwrap(parts.first { $0.nodes.map(\.point.x).min()! > 9 })
        XCTAssertEqual(left.holeRings.count, 1)
        XCTAssertNil(right.holes)
        XCTAssertEqual(filled(left) + filled(right), 200 - 16, accuracy: 1e-6)
    }

    func testSplitThroughHoleSplitsIt() throws {
        let parts = try donut.splittingArea(along: [BezierNode(point: P(10, -2)), BezierNode(point: P(10, 22))]).get()
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts.allSatisfy { $0.holes == nil }, "The hole became a notch in both halves")
        for p in parts { XCTAssertEqual(filled(p), 150, accuracy: 1e-6) }
    }

    func testSplitFromEdgeIntoHoleOnlyIsRejected() {
        XCTAssertEqual(donut.splittingArea(along: [BezierNode(point: P(10, -2)), BezierNode(point: P(10, 8))]), .failure(.notCrossing))
        // Across the hole only, from hole edge to hole edge: nothing filled is crossed.
        XCTAssertEqual(donut.splittingArea(along: [BezierNode(point: P(5, 10)), BezierNode(point: P(15, 10))]), .failure(.notCrossing))
        // Inside the hole without touching anything.
        XCTAssertEqual(donut.splittingArea(along: [BezierNode(point: P(6, 10)), BezierNode(point: P(14, 10))]), .failure(.noOverlap))
    }

    // MARK: Merge

    func testMergeFormingRingMakesHole() throws {
        // Two U shapes snapped together into a ring (shared sides at both ends): auto merge keeps the gap as a hole.
        let left = area(ring([(0, 0), (10, 0), (10, 5), (5, 5), (5, 15), (10, 15), (10, 20), (0, 20)]))
        let right = area(ring([(10, 0), (20, 0), (20, 20), (10, 20), (10, 15), (15, 15), (15, 5), (10, 5)]))
        let r = try XCTUnwrap(left.unitingArea(right, vertexTolerance: 0.01, flattenTolerance: 0.1, allowOverlap: false))
        XCTAssertTrue(r.formedHole)
        XCTAssertFalse(r.flattenedCurves)
        XCTAssertEqual(r.feature.holeRings.count, 1)
        XCTAssertEqual(filled(r.feature), 400 - 100, accuracy: 1e-6)
    }

    func testMergeKeepsHolesOfBothAreas() throws {
        var a = area(rect(0, 0, 10, 10))
        a.holes = [rect(2, 2, 4, 4)]
        a.normalizeHoles()
        var b = area(rect(10, 0, 20, 10))
        b.holes = [rect(12, 2, 14, 4)]
        b.normalizeHoles()
        let stitched = try XCTUnwrap(a.unitingArea(b, vertexTolerance: 0.01, flattenTolerance: 0.1, allowOverlap: false))
        XCTAssertEqual(stitched.feature.holeRings.count, 2)
        XCTAssertFalse(stitched.formedHole)
        XCTAssertEqual(filled(stitched.feature), 200 - 8, accuracy: 1e-6)
        // Overlapping area covering part of a hole: the hole shrinks.
        let c = area(rect(3, 3, 8, 8))
        let r = try XCTUnwrap(a.unitingArea(c, vertexTolerance: 0.01, flattenTolerance: 0.1))
        XCTAssertEqual(r.feature.holeRings.count, 1)
        XCTAssertEqual(filled(r.feature), 100 - 3, accuracy: 1e-6)
        // An area filling the hole exactly removes it.
        let plug = area(rect(2, 2, 4, 4))
        let full = try XCTUnwrap(a.unitingArea(plug, vertexTolerance: 0.01, flattenTolerance: 0.1))
        XCTAssertNil(full.feature.holes)
        XCTAssertEqual(filled(full.feature), 100, accuracy: 1e-6)
    }

    func testMergeOverlapKeepsCurves() throws {
        let circle = Feature.ellipse(corners: [P(5, 15), P(15, 15), P(15, 5), P(5, 5)], colorHex: "#000", widthMM: 0)
        let r = try XCTUnwrap(square.unitingArea(area(circle.nodes), vertexTolerance: 0.01, flattenTolerance: 0.1))
        XCTAssertFalse(r.flattenedCurves, "Exact union: the circle's curves stay curves")
        XCTAssertTrue(r.feature.nodes.contains(where: \.isSmooth))
    }

    // MARK: Import / export

    private let zone = UTMZone(epsg: 32748)!
    private let sheet = SheetSpec(scaleDenominator: 4000)
    private var frame: MapFrame { MapFrame(origin: P(787_000, 9_234_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM) }

    private var mapDonut: Feature {
        let o = frame.origin
        var f = area(rect(o.x + 100, o.y + 100, o.x + 300, o.y + 300))
        f.holes = [rect(o.x + 150, o.y + 150, o.x + 250, o.y + 250)]
        f.normalizeHoles()
        return f
    }

    func testOmapRoundTripKeepsHole() throws {
        let req = VectorExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: zone, strokes: [], features: [mapDonut])
        let coords = OmapWriter.featureCoords(mapDonut, reference: frame.center, scale: 4000)
        XCTAssertEqual(coords.count, 10, "4 + closing point, twice")
        XCTAssertTrue(coords[4].hasSuffix(" 18;"), "Outer ring ends with close + hole flags")
        XCTAssertTrue(coords[9].hasSuffix(" 2;"), "Last part ends with the close flag only")
        let (features, report) = try OmapReader.read(Data(OmapWriter.document(req).utf8), zone: zone)
        XCTAssertEqual(report.droppedHoles, 0)
        let f = try XCTUnwrap(features.first)
        XCTAssertEqual(f.holeRings.count, 1)
        XCTAssertEqual(f.holeRings[0].count, 4)
        XCTAssertEqual(f.filledArea(tolerance: 0.01), 200 * 200 - 100 * 100, accuracy: 1)
        XCTAssertLessThan(Feature.signedArea(of: f.nodes) * Feature.signedArea(of: f.holeRings[0]), 0)
    }

    func testDXFWritesHoleAsSeparatePolyline() {
        let req = VectorExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: zone, strokes: [], features: [mapDonut])
        let dxf = DXFWriter.document(req)
        let layer = "406_0_FOREST"
        XCTAssertEqual(dxf.components(separatedBy: "POLYLINE\r\n8\r\n\(layer)").count - 1, 2, "Outer ring + hole on the same layer")
    }

    func testPDFUsesEvenOddFill() {
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "uji", frame: frame, sheet: sheet, zone: zone,
                                                                         strokes: [], features: [mapDonut])), as: UTF8.self)
        XCTAssertTrue(pdf.contains("h\nf*\n"), "Area with its hole filled with the even-odd rule")
        XCTAssertEqual(pdf.components(separatedBy: " m\n").count - 1 >= 2, true, "Outer ring and hole as subpaths")
    }

    func testRasterLeavesHoleEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let req = RasterExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: zone, dpi: 150, format: .png,
                                      strokes: [], features: [mapDonut])
        let result = try RasterExporter.export(req, to: dir)
        let wf = try XCTUnwrap(WorldFile(text: String(contentsOf: result.worldFileURL)))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(result.imageURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        func green(at p: Point2D) -> Bool {
            let col = Int(((p.x - wf.upperLeftX) / wf.pixelSizeX).rounded())
            let row = Int(((p.y - wf.upperLeftY) / wf.pixelSizeY).rounded())
            let i = (row * image.width + col) * 4
            return data[i + 1] > 150 && data[i] < 120
        }
        let o = frame.origin
        XCTAssertTrue(green(at: P(o.x + 120, o.y + 120)), "Filled part")
        XCTAssertFalse(green(at: P(o.x + 200, o.y + 200)), "The hole stays empty")
    }

    func testOcadImportKeepsCurvedHole() throws {
        // Outer square, then a hole starting with the hole flag whose second segment is a curve.
        let pts: [(Int32, Int32, UInt8, UInt8)] = [(0, 0, 0, 0), (1000, 0, 0, 0), (1000, 1000, 0, 0), (0, 1000, 0, 0), (0, 0, 0, 0),
                                                   (200, 200, 0, 2), (600, 200, 0, 0), (700, 300, 1, 0), (700, 500, 0, 0),
                                                   (600, 600, 0, 0), (200, 600, 0, 0), (200, 200, 0, 0)]
        let map = try OcadReader.read(OcadReaderTests.makeOcad(objects: [(526_000, 3, pts)]))
        let f = try XCTUnwrap(map.features().features.first)
        XCTAssertEqual(f.nodes.count, 4)
        XCTAssertEqual(f.holeRings.count, 1)
        XCTAssertEqual(f.holeRings[0].count, 4)
        XCTAssertTrue(f.holeRings[0].contains(where: \.isSmooth), "Bezier in the hole read as a curve")
    }
}
