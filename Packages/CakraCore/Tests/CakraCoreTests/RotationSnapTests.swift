import XCTest
@testable import CakraCore

/// Rotasi presisi (Shift): sisi lurus objek menempel sejajar/tegak lurus dengan sisi lurus objek lain.
final class RotationSnapTests: XCTestCase {
    private func P(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }
    private func line(_ pts: [Point2D]) -> Feature {
        Feature(kind: .line, colorHex: "#000000", widthMM: 0.3, nodes: pts.map { BezierNode(point: $0) })
    }

    func testBearingOfLineDirection() {
        XCTAssertEqual(RotationSnap.bearing(P(0, 0), P(0, 10)), 0, accuracy: 1e-9)
        XCTAssertEqual(RotationSnap.bearing(P(0, 0), P(10, 0)), 90, accuracy: 1e-9)
        XCTAssertEqual(RotationSnap.bearing(P(0, 0), P(-10, 0)), 90, accuracy: 1e-9, "Arah garis, bukan vektor")
        XCTAssertEqual(RotationSnap.bearing(P(0, 0), P(10, 10)), 45, accuracy: 1e-9)
    }

    func testLineSnapsParallelToNeighbourEdge() {
        // Garis mendatar (90°) diputar ~28° → mendekati sisi tetangga berarah 120° (90 + 30): menempel tepat.
        let moving = line([P(0, 0), P(20, 0)])
        let neighbour = line([P(50, 0), P(50 + 10 * sin(120 * .pi / 180), 10 * cos(120 * .pi / 180))])
        let r = RotationSnap.snap(raw: 28, base: 0, edges: moving.straightEdges(minLength: 1),
                                  references: neighbour.straightEdges(minLength: 1), includeNorth: false)
        XCTAssertEqual(r.degrees, 30, accuracy: 1e-9)
        XCTAssertFalse(r.isStep)
        XCTAssertNotNil(r.reference)
    }

    func testPerpendicularAlsoSnaps() {
        // Sisi tetangga 120° → tegak lurusnya 30°: garis 90° yang diputar ~−58° (bearing 32°) menempel ke 30°.
        let moving = line([P(0, 0), P(20, 0)])
        let neighbour = line([P(50, 0), P(50 + 10 * sin(120 * .pi / 180), 10 * cos(120 * .pi / 180))])
        let r = RotationSnap.snap(raw: -58, base: 0, edges: moving.straightEdges(minLength: 1),
                                  references: neighbour.straightEdges(minLength: 1), includeNorth: false)
        XCTAssertEqual(r.degrees, 300, accuracy: 1e-9, "−60° = 300°")
    }

    func testFarFromAnyEdgeFallsBackToSymmetricSteps() {
        let moving = line([P(0, 0), P(20, 0)])
        let neighbour = line([P(50, 0), P(50, 10)])   // 0°: acuan di 0/90/180/270
        let r = RotationSnap.snap(raw: 38, base: 0, edges: moving.straightEdges(minLength: 1),
                                  references: neighbour.straightEdges(minLength: 1), includeNorth: false)
        XCTAssertTrue(r.isStep)
        XCTAssertEqual(r.degrees, 45, accuracy: 1e-9, "Kelipatan 15° terdekat")
    }

    func testExactRotationKeepsEdgeExactlyParallel() {
        var f = line([P(0, 0), P(20, 0)])
        f.setRotationExactly(30.123456)
        let e = f.straightEdges(minLength: 1)[0]
        XCTAssertEqual(e.bearing, 120.123456, accuracy: 1e-6, "Tanpa pembulatan 0,1°")
        XCTAssertEqual(f.rotationDegrees, 30.123456, accuracy: 1e-9)
    }
}
