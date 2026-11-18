import XCTest
@testable import CakraCore

/// Corner Tool: rounding selected corners of areas (holes too) and lines.
final class FeatureCornersTests: XCTestCase {
    private func P(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    private func ring(_ pts: [(Double, Double)]) -> [BezierNode] { pts.map { BezierNode(point: P($0.0, $0.1)) } }

    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [BezierNode] {
        ring([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    }

    private func area(_ nodes: [BezierNode]) -> Feature {
        Feature(name: "Building", kind: .area, colorHex: "#000000", widthMM: 0, nodes: nodes, symbolCode: "521.1", symbolName: "Building")
    }

    private func line(_ pts: [(Double, Double)]) -> Feature {
        Feature(name: "Path", kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: ring(pts), symbolCode: "507.0", symbolName: "Path")
    }

    private func assertClose(_ a: Point2D?, _ b: Point2D, accuracy: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        guard let a else { return XCTFail("nil point", file: file, line: line) }
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, file: file, line: line)
    }

    func testSquareOneRoundedCorner() throws {
        let square = area(rect(0, 0, 10, 10))
        let c = try XCTUnwrap(square.corner(at: 2))
        XCTAssertEqual(c.interiorAngle, .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(c.maxRadius, 5, accuracy: 1e-12)
        assertClose(c.bisector, P(-1 / 2.0.squareRoot(), -1 / 2.0.squareRoot()))

        let r = square.roundingCorners([2], radius: 2)
        XCTAssertEqual(r.id, square.id)
        XCTAssertEqual(r.symbolCode, "521.1")
        XCTAssertEqual(r.nodes.count, 5)
        // Corner (10,10) → tangent points 2 m along both edges.
        assertClose(r.nodes[2].point, P(10, 8))
        assertClose(r.nodes[3].point, P(8, 10))
        let k = 4.0 / 3.0 * tan(Double.pi / 8) * 2   // 0.5523 · r
        assertClose(r.nodes[2].outHandle, P(10, 8 + k))
        assertClose(r.nodes[3].inHandle, P(8 + k, 10))
        XCTAssertNil(r.nodes[2].inHandle)
        XCTAssertNil(r.nodes[3].outHandle)
        // The other corners stay sharp.
        for i in [0, 1, 4] { XCTAssertFalse(r.nodes[i].isSmooth) }
        // The arc's middle lies on the circle around (8,8).
        let mid = r.segments[2].point(at: 0.5)
        XCTAssertEqual(mid.distance(to: P(8, 8)), 2, accuracy: 0.001)
        // Area: the square minus the corner piece (r² − πr²/4).
        XCTAssertEqual(r.filledArea(tolerance: 0.0005), 100 - (4 - .pi), accuracy: 0.01)
    }

    func testStraightCornerIsAChamfer() {
        let r = area(rect(0, 0, 10, 10)).roundingCorners([2], radius: 2, style: .straight)
        XCTAssertEqual(r.nodes.count, 5)
        XCTAssertFalse(r.nodes.contains { $0.isSmooth })
        XCTAssertEqual(r.filledArea(tolerance: 0.0005), 98, accuracy: 1e-9)
    }

    func testAreaWithHoleRoundsHoleCorners() {
        var donut = area(rect(0, 0, 20, 20))
        donut.holes = [rect(5, 5, 15, 15)]
        donut.normalizeHoles()
        // Index 4 = first node of the hole (Node Tool indices continue after the outer ring).
        let r = donut.roundingCorners([0, 4], radius: 1)
        XCTAssertEqual(r.nodes.count, 5)
        XCTAssertEqual(r.holeRings.count, 1)
        XCTAssertEqual(r.holeRings[0].count, 5)
        XCTAssertLessThan(Feature.signedArea(of: r.holeRings[0]) * Feature.signedArea(of: r.nodes), 0, "Hole keeps its winding")
        // Outer corner loses (1 − π/4); the hole corner gives back (1 − π/4).
        XCTAssertEqual(r.filledArea(tolerance: 0.0005), 300, accuracy: 0.01)
        XCTAssertEqual(r.roundingCorners([], radius: 1), r)
    }

    func testOpenLineRoundsInteriorCornerOnly() {
        let l = line([(0, 0), (10, 0), (10, 10)])
        XCTAssertNil(l.corner(at: 0), "Line ends are not corners")
        XCTAssertNil(l.corner(at: 2))
        XCTAssertEqual(l.roundableCornerIndices, [1])
        let r = l.roundingCorners([0, 1, 2], radius: 3)
        XCTAssertEqual(r.kind, .line)
        XCTAssertEqual(r.nodes.count, 4)
        assertClose(r.nodes[0].point, P(0, 0))
        assertClose(r.nodes[1].point, P(7, 0))
        assertClose(r.nodes[2].point, P(10, 3))
        assertClose(r.nodes[3].point, P(10, 10))
        XCTAssertNil(r.nodes[0].outHandle)
        XCTAssertNil(r.nodes[3].inHandle)
    }

    func testClampingNeverOverlaps() throws {
        // 4 × 10 rectangle, all corners with a radius far too large: each tangent distance stops at half the short edge.
        let f = area(rect(0, 0, 4, 10))
        XCTAssertEqual(try XCTUnwrap(f.corner(at: 0)).effectiveRadius(50), 2, accuracy: 1e-12)
        let r = f.roundingCorners([0, 1, 2, 3], radius: 50)
        // Two roundings meet in the middle of each short edge: those points are merged (8 − 2 nodes).
        XCTAssertEqual(r.nodes.count, 6)
        for (a, b) in zip(r.nodes, r.nodes.dropFirst() + [r.nodes[0]]) {
            XCTAssertGreaterThan(a.point.distance(to: b.point), 1e-6)
        }
        XCTAssertTrue(r.nodes.contains { $0.point.distance(to: P(2, 0)) < 1e-9 })
        XCTAssertTrue(r.nodes.contains { $0.point.distance(to: P(2, 10)) < 1e-9 })
        // A stadium: rectangle minus 4 corner pieces of radius 2.
        XCTAssertEqual(r.filledArea(tolerance: 0.0005), 40 - 4 * (4 - .pi), accuracy: 0.02)
    }

    func testZeroRadiusAndStraightThroughNodesUnchanged() {
        let square = area(rect(0, 0, 10, 10))
        XCTAssertEqual(square.roundingCorners([0, 1, 2, 3], radius: 0), square)
        XCTAssertEqual(square.roundingCorners([0], radius: -1), square)
        let withMid = area(ring([(0, 0), (5, 0), (10, 0), (10, 10), (0, 10)]))
        XCTAssertNil(withMid.corner(at: 1), "Collinear node")
        XCTAssertEqual(withMid.roundingCorners([1], radius: 2), withMid)
        let ellipse = Feature.ellipse(corners: [P(0, 10), P(10, 10), P(10, 0), P(0, 0)], colorHex: "#000000", widthMM: 0)
        XCTAssertTrue(ellipse.roundableCornerIndices.isEmpty, "Smooth nodes are not corners")
        XCTAssertNil(Feature(kind: .point, colorHex: "#000000", widthMM: 1, nodes: [BezierNode(point: P(0, 0))]).corner(at: 0))
    }

    func testCurvedNeighbourIsSplitOnTheCurve() throws {
        // Triangle whose bottom edge (0,0) → (10,0) bulges downward.
        var f = area(ring([(0, 0), (10, 0), (5, 8)]))
        f.nodes[0].outHandle = P(3, -3)
        f.nodes[1].inHandle = P(7, -3)
        let original = f.segments[0]
        let c = try XCTUnwrap(f.corner(at: 1))
        // The corner is measured along the curve's tangent at the node (toward its handle).
        let toHandle = P(-3, -3) * (1 / 18.0.squareRoot())
        assertClose(c.towardPrevious, toHandle)
        let r = f.roundingCorners([1], radius: 1)
        XCTAssertEqual(r.nodes.count, 4)
        // The new node on the curved edge lies on the original curve, and the arc leaves it along the curve (smooth join).
        let start = r.nodes[1]
        XCTAssertLessThan(original.nearest(to: start.point).distance, 1e-3)
        let inDir = try XCTUnwrap(start.inHandle) - start.point, outDir = try XCTUnwrap(start.outHandle) - start.point
        let cross = (inDir.x * outDir.y - inDir.y * outDir.x) / (hypot(inDir.x, inDir.y) * hypot(outDir.x, outDir.y))
        XCTAssertEqual(cross, 0, accuracy: 1e-6)
        XCTAssertLessThan(inDir.x * outDir.x + inDir.y * outDir.y, 0)
        // The untouched part of the curve keeps its shape: the start of the edge is unchanged.
        assertClose(r.nodes[0].point, P(0, 0))
        assertClose(r.segments[0].point(at: 0.25), original.sub(0, Feature.parameter(original, atLength: Feature.arcLength(original) - c.tangentDistance(radius: 1))).point(at: 0.25))
    }
}
