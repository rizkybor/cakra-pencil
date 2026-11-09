@testable import CakraCore
import XCTest

/// Cut leg: a gap in the course line splits the leg into two pieces; gaps belong to one leg of one course.
final class LegGapTests: XCTestCase {
    private func legs(_ o: CourseOverprint) -> [[Point2D]] {
        o.marks.compactMap { if case let .polyline(p, closed) = $0, !closed, p.count == 2 { return p } else { return nil } }
    }

    func testGapSplitsLeg() {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let s = ControlPoint(kind: .start, code: nil, position: Point2D(x: 0, y: 0))
        let c = ControlPoint(kind: .control, code: 31, position: Point2D(x: 400, y: 0))
        var course = Course(name: "A", controlIDs: [s.id, c.id])
        let plain = CourseOverprint.make(CourseSet(controls: [s, c], courses: [course]), course: course, sheet: sheet)
        XCTAssertEqual(legs(plain).count, 1, "One leg without gaps")

        course.legGaps = [LegGap(from: s.id, to: c.id, at: 0.5)]
        let cut = CourseOverprint.make(CourseSet(controls: [s, c], courses: [course]), course: course, sheet: sheet)
        let pieces = legs(cut)
        XCTAssertEqual(pieces.count, 2, "Gap splits the leg")
        // 2.5 mm at 1:4000 = 10 m, centred at x = 200.
        XCTAssertEqual(pieces[0][1].x, 195, accuracy: 0.01)
        XCTAssertEqual(pieces[1][0].x, 205, accuracy: 0.01)

        // The All controls view has no legs, so no gaps either.
        XCTAssertTrue(legs(CourseOverprint.make(CourseSet(controls: [s, c], courses: [course]), course: nil, sheet: sheet)).isEmpty)
    }

    func testOldCourseFilesDecodeWithoutGaps() throws {
        let json = #"{"id":"6B8C2D1A-0000-4000-8000-000000000001","name":"A","kind":"normal","controlIDs":[],"competitors":0}"#
        let course = try JSONDecoder().decode(Course.self, from: Data(json.utf8))
        XCTAssertNil(course.legGaps)
    }
}
