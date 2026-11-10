import XCTest
@testable import CakraCore

/// Cutting areas with a shape/path and cutting lines with a box (see FeatureCut.swift).
final class FeatureCutTests: XCTestCase {
    private func P(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    private func area(_ pts: [(Double, Double)]) -> Feature {
        var f = Feature(name: "Forest", kind: .area, colorHex: "#3CB54A", widthMM: 0,
                        nodes: pts.map { BezierNode(point: P($0.0, $0.1)) })
        f.symbolCode = "406.0"
        return f
    }

    private func line(_ pts: [(Double, Double)]) -> Feature {
        var f = Feature(name: "Path", kind: .line, colorHex: "#000000", widthMM: 0.25,
                        nodes: pts.map { BezierNode(point: P($0.0, $0.1)) })
        f.symbolCode = "506.0"
        return f
    }

    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [BezierNode] {
        [(x0, y0), (x1, y0), (x1, y1), (x0, y1)].map { BezierNode(point: P($0.0, $0.1)) }
    }

    private func polygonArea(_ f: Feature) -> Double {
        abs(ShapeCut.signedArea(f.flattened(tolerance: 0.0005)))
    }

    private let square = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]

    // MARK: Area − shape

    func testRectangleAcrossOneEdge() throws {
        let f = area(square)
        let parts = try f.subtractingShape(rect(8, 2, 14, 6)).get()
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].id, f.id)
        XCTAssertEqual(parts[0].symbolCode, "406.0")
        XCTAssertEqual(polygonArea(parts[0]), 100 - 2 * 4, accuracy: 1e-6)
        // Original corners kept, a notch of 4 new corners.
        XCTAssertEqual(parts[0].nodes.count, 8)
        for corner in square { XCTAssertTrue(parts[0].nodes.contains { $0.point.distance(to: P(corner.0, corner.1)) < 1e-9 }) }
    }

    func testRectangleCutsCorner() throws {
        let parts = try area(square).subtractingShape(rect(5, 5, 12, 12)).get()
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(polygonArea(parts[0]), 75, accuracy: 1e-6)
        XCTAssertEqual(parts[0].nodes.count, 6)
    }

    func testStripSplitsAreaInTwo() throws {
        let f = area(square)
        let parts = try f.subtractingShape(rect(4, -2, 6, 12)).get()
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.map(polygonArea).reduce(0, +), 80, accuracy: 1e-6)
        XCTAssertEqual(parts[0].id, f.id)
        XCTAssertNotEqual(parts[1].id, f.id)
        XCTAssertEqual(parts[1].symbolCode, "406.0")
        XCTAssertEqual(parts[1].colorHex, f.colorHex)
        for p in parts { XCTAssertEqual(polygonArea(p), 40, accuracy: 1e-6) }
    }

    func testShapeInsideMakesHoleOrNoOp() throws {
        let holed = try area(square).subtractingShape(rect(2, 2, 4, 4)).get()
        XCTAssertEqual(holed.count, 1)
        XCTAssertEqual(holed[0].holeRings.count, 1, "A shape completely inside punches a hole")
        XCTAssertEqual(area(square).subtractingShape(rect(20, 20, 30, 30)), .failure(.noOverlap))
        XCTAssertEqual(try area(square).subtractingShape(rect(-1, -1, 11, 11)).get(), [], "Covered completely")
    }

    func testShapeSharingAnEdge() throws {
        // Shape on the outside, touching along the right edge: nothing to cut.
        XCTAssertEqual(area(square).subtractingShape(rect(10, 2, 14, 6)), .failure(.noOverlap))
        // Shape inside, sharing part of the right edge (collinear): a notch.
        let parts = try area(square).subtractingShape(rect(8, 2, 10, 6)).get()
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(polygonArea(parts[0]), 92, accuracy: 1e-6)
    }

    func testClockwiseAreaAndShapeThroughCorners() throws {
        // Clockwise area; the cut runs exactly through two of its corners (points on the edge).
        let f = area(square.reversed())
        let parts = try f.subtractingShape(rect(-2, -2, 10, 10)).get()
        XCTAssertEqual(parts, [], "The shape covers the area exactly")
        let tri = try f.subtractingShape([BezierNode(point: P(0, 0)), BezierNode(point: P(10, 0)), BezierNode(point: P(10, 10))]).get()
        XCTAssertEqual(tri.count, 1)
        XCTAssertEqual(polygonArea(tri[0]), 50, accuracy: 1e-6)
        XCTAssertLessThan(tri[0].signedArea, 0, "Original (clockwise) direction kept")
    }

    func testEllipseCutKeepsCurves() throws {
        let f = area(square)
        let e = Feature.ellipse(corners: [P(6, 14), P(14, 14), P(14, 6), P(6, 6)], colorHex: "#000", widthMM: 0)
        let parts = try f.subtractingShape(e.nodes).get()
        XCTAssertEqual(parts.count, 1)
        // A quarter of a circle with radius 4 removed.
        XCTAssertEqual(polygonArea(parts[0]), 100 - .pi * 16 / 4, accuracy: 0.05)
        XCTAssertTrue(parts[0].nodes.contains(where: \.isSmooth), "The cut edge follows the ellipse as a curve")
    }

    func testCurvedAreaKeepsUntouchedCurves() throws {
        // Circle-like area (4 curves); a rectangle removes the right part.
        let circle = Feature.ellipse(corners: [P(-10, 10), P(10, 10), P(10, -10), P(-10, -10)], colorHex: "#000", widthMM: 0)
        var f = area(square)
        f.nodes = circle.nodes
        let parts = try f.subtractingShape(rect(5, -20, 20, 20)).get()
        XCTAssertEqual(parts.count, 1)
        let curves = parts[0].segments.filter(\.isCurve).count
        XCTAssertGreaterThanOrEqual(curves, 3, "The left curves stay curves")
        XCTAssertLessThan(parts[0].nodes.map(\.point.x).max()!, 5 + 1e-6)
    }

    // MARK: Split along a path

    func testPathSplitTwoCrossings() throws {
        let f = area(square)
        let path = [P(-2, 3), P(5, 6), P(12, 3)].map { BezierNode(point: $0) }
        let parts = try f.splittingArea(along: path).get()
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.map(polygonArea).reduce(0, +), 100, accuracy: 1e-6)
        XCTAssertEqual(parts[0].id, f.id)
    }

    func testPathSplitFourCrossings() throws {
        // A zigzag that leaves the area through the right edge and comes back: 4 crossings → 3 pieces.
        let path = [P(-2, 2), P(12, 2), P(12, 8), P(-2, 8)].map { BezierNode(point: $0) }
        let parts = try area(square).splittingArea(along: path).get()
        XCTAssertEqual(parts.count, 3)
        let areas = parts.map(polygonArea).sorted()
        XCTAssertEqual(areas[0], 20, accuracy: 1e-6)
        XCTAssertEqual(areas[1], 20, accuracy: 1e-6)
        XCTAssertEqual(areas[2], 60, accuracy: 1e-6)
    }

    func testPathSplitFromEdgeToEdgeAndCurvedPath() throws {
        // Starts and ends exactly on the edge (snapped), curved in between.
        let path = [BezierNode(point: P(0, 5), outHandle: P(3, 9)), BezierNode(point: P(10, 5), inHandle: P(7, 1))]
        let parts = try area(square).splittingArea(along: path).get()
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.map(polygonArea).reduce(0, +), 100, accuracy: 0.01)
        XCTAssertTrue(parts.allSatisfy { $0.nodes.contains(where: \.isSmooth) }, "Both pieces get the curved edge")
    }

    func testPathNotCrossing() {
        let inside = [P(2, 2), P(8, 8)].map { BezierNode(point: $0) }
        XCTAssertEqual(area(square).splittingArea(along: inside), .failure(.notCrossing))
        let once = [P(-2, 5), P(5, 5)].map { BezierNode(point: $0) }
        XCTAssertEqual(area(square).splittingArea(along: once), .failure(.notCrossing))
        let outside = [P(20, 0), P(30, 10)].map { BezierNode(point: $0) }
        XCTAssertEqual(area(square).splittingArea(along: outside), .failure(.noOverlap))
    }

    // MARK: Line − box

    private func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Point2D] {
        [P(x0, y0), P(x1, y0), P(x1, y1), P(x0, y1)]
    }

    func testLineBoxCutMiddle() throws {
        let f = line([(0, 0), (10, 0), (20, 0)])
        let parts = try XCTUnwrap(f.cuttingOut(box(8, -1, 12, 1)))
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].id, f.id)
        XCTAssertNotEqual(parts[1].id, f.id)
        XCTAssertEqual(parts[0].nodes.map(\.point), [P(0, 0), P(8, 0)])
        XCTAssertEqual(parts[1].nodes.map(\.point), [P(12, 0), P(20, 0)])
        XCTAssertEqual(parts[1].symbolCode, "506.0")
    }

    func testLineBoxCoversEnd() throws {
        let parts = try XCTUnwrap(line([(0, 0), (10, 0), (20, 0)]).cuttingOut(box(15, -1, 25, 1)))
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].nodes.map(\.point), [P(0, 0), P(10, 0), P(15, 0)])
    }

    func testLineBoxCoversAllOrNothing() {
        XCTAssertEqual(line([(0, 0), (10, 0), (20, 0)]).cuttingOut(box(-1, -1, 21, 1)), [])
        XCTAssertNil(line([(0, 0), (10, 0), (20, 0)]).cuttingOut(box(0, 5, 10, 8)), "Box beside the line")
    }

    func testLineBoxCrossingSeveralTimes() throws {
        // Zigzag line through a box: the line enters and leaves twice → 3 pieces.
        let parts = try XCTUnwrap(line([(0, 0), (10, 0), (10, 4), (0, 4)]).cuttingOut(box(4, -1, 6, 5)))
        XCTAssertEqual(parts.count, 3)
    }

    func testBezierLineBoxCut() throws {
        // One S-curve; the box removes its middle. The pieces stay curves and end exactly on the box edge.
        let f = Feature(kind: .line, colorHex: "#000", widthMM: 0.25, nodes: [
            BezierNode(point: P(0, 0), outHandle: P(5, 10)),
            BezierNode(point: P(20, 0), inHandle: P(15, -10)),
        ])
        let parts = try XCTUnwrap(f.cuttingOut(box(8, -10, 12, 10)))
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].nodes.last!.point.x, 8, accuracy: 1e-6)
        XCTAssertEqual(parts[1].nodes.first!.point.x, 12, accuracy: 1e-6)
        XCTAssertTrue(parts.allSatisfy { $0.segments.allSatisfy(\.isCurve) })
        // The remaining pieces lie exactly on the original curve.
        for p in parts {
            for s in p.segments {
                XCTAssertLessThan(f.distance(to: s.point(at: 0.5), tolerance: 0.0001), 0.001)
            }
        }
    }

    func testClosedLineBoxCut() throws {
        // Closed line (ring): a box over one side opens it into a single line around the other three sides.
        let f = line([(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)])
        XCTAssertTrue(f.isRingLine)
        let parts = try XCTUnwrap(f.cuttingOut(box(3, -1, 7, 1)))
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].nodes.first!.point, P(7, 0))
        XCTAssertEqual(parts[0].nodes.last!.point, P(3, 0))
        XCTAssertEqual(parts[0].nodes.count, 6)
        // Box over the start corner: the start point disappears, still one line.
        let corner = try XCTUnwrap(f.cuttingOut(box(-1, -1, 2, 2)))
        XCTAssertEqual(corner.count, 1)
        XCTAssertEqual(corner[0].nodes.first!.point, P(2, 0))
        XCTAssertEqual(corner[0].nodes.last!.point, P(0, 2))
    }

    func testRotatedBox() throws {
        // A box rotated 45° (map rotation): cut exactly where its edges cross the line.
        let c = P(10, 0), r = 2.0
        let diamond = [P(c.x, c.y - r), P(c.x + r, c.y), P(c.x, c.y + r), P(c.x - r, c.y)]
        let parts = try XCTUnwrap(line([(0, 0), (20, 0)]).cuttingOut(diamond))
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].nodes.last!.point.x, 8, accuracy: 1e-9)
        XCTAssertEqual(parts[1].nodes.first!.point.x, 12, accuracy: 1e-9)
    }
}
