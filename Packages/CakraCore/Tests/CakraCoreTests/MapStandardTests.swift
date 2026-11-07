import CakraCore
import XCTest

/// IOF ISOM 2017-2 / ISSprOM 2019-2 (Revision 6, January 2024) sizes OCCA applies.
final class MapStandardTests: XCTestCase {
    private func eq(_ a: Double, _ b: Double, _ msg: String = "") { XCTAssertEqual(a, b, accuracy: 1e-9, msg) }

    func testStandardAndEnlargement() {
        XCTAssertEqual(MapStandard.for(scale: 4000), .issprom)
        XCTAssertEqual(MapStandard.for(scale: 5000), .issprom)
        XCTAssertEqual(MapStandard.for(scale: 10000), .isom)
        eq(MapStandard.isom.enlargement(scale: 15000), 1)
        eq(MapStandard.isom.enlargement(scale: 10000), 1.5, "ISOM §2.9.1: 1:10000 = 150%")
        eq(MapStandard.issprom.enlargement(scale: 4000), 1)
        eq(MapStandard.issprom.enlargement(scale: 3000), 4.0 / 3, "ISSprOM §3.1: 1:3000 = 133%")
        eq(MapStandard.issprom.enlargement(scale: 5000), 1, "Never reduced")
    }

    func testCourseSymbols() {
        let forest = CourseStyle.standard(scale: 15000)
        eq(forest.controlDiameterMM, 5); eq(forest.startSideMM, 6); eq(forest.lineWidthMM, 0.35)
        eq(forest.finishInnerMM, 4, "ISOM 706 ø4.0"); eq(forest.finishOuterMM, 6, "ISOM 706 ø6.0"); eq(forest.numberHeightMM, 4)
        let enlarged = CourseStyle.standard(scale: 10000)
        eq(enlarged.controlDiameterMM, 7.5); eq(enlarged.startSideMM, 9); eq(enlarged.finishInnerMM, 6); eq(enlarged.finishOuterMM, 9)
        eq(enlarged.lineWidthMM, 0.525); eq(enlarged.numberHeightMM, 6)
        let sprint = CourseStyle.standard(scale: 4000)
        eq(sprint.controlDiameterMM, 6); eq(sprint.startSideMM, 7); eq(sprint.lineWidthMM, 0.35)
        eq(sprint.finishInnerMM, 5, "ISSprOM 706 ø5.0"); eq(sprint.finishOuterMM, 7, "ISSprOM 706 ø7.0")
        eq(CourseStyle.standard(scale: 3000).controlDiameterMM, 8)
    }

    func testControlNumberIsFontSize() {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let c = ControlPoint(kind: .control, code: 31, position: Point2D(x: 0, y: 0))
        let course = Course(name: "A", controlIDs: [c.id])
        let set = CourseSet(controls: [c], courses: [course])
        let o = CourseOverprint.make(set, course: course, sheet: sheet)
        let heights = o.marks.compactMap { m -> Double? in if case let .text(_, _, h) = m { return h } else { return nil } }
        XCTAssertFalse(heights.isEmpty)
        // Arial 4.0 mm font → digits ≈ 2.86 mm tall → 11.5 m on the ground at 1:4000.
        eq(heights[0], 4 * CourseStyle.digitHeightPerFontSize * 4)
    }

    func testContourAndFormLines() {
        let forest = ContourSettings.defaults(scale: 15000)
        eq(forest.contourWidthMM, 0.14); eq(forest.indexWidthMM, 0.25)
        let enlarged = ContourSettings.defaults(scale: 10000)
        eq(enlarged.contourWidthMM, 0.21); eq(enlarged.indexWidthMM, 0.375)
        let sprint = ContourSettings.defaults(scale: 4000)
        eq(sprint.contourWidthMM, 0.21, "ISSprOM 101"); eq(sprint.indexWidthMM, 0.30, "ISSprOM 102")
        let isomForm = ContourSettings.formLine(contourWidthMM: 0.14)
        eq(isomForm.width, 0.1); eq(isomForm.dash[0], 2.0); eq(isomForm.dash[1], 0.2)
        let sprintForm = ContourSettings.formLine(contourWidthMM: 0.21)
        eq(sprintForm.width, 0.15); eq(sprintForm.dash[0], 3.0); eq(sprintForm.dash[1], 0.3)
        let line = ContourLine(elevation: 12.5, kind: .form, points: [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)], isClosed: false)
        let f = line.feature(settings: sprint)
        eq(f.widthMM, 0.15); XCTAssertEqual(f.dashMM?.count, 2)
    }

    func testNorthLines() {
        let forest = NorthGrid.standard(scale: 15000)
        eq(forest.spacingM, 300, "ISOM 601: 20 mm at 1:15000"); eq(forest.lineWidthMM, 0.12)
        eq(forest.spacingPaperMM(scale: 15000), 20)
        let enlarged = NorthGrid.standard(scale: 10000)
        eq(enlarged.spacingM, 300); eq(enlarged.lineWidthMM, 0.18)
        let sprint = NorthGrid.standard(scale: 4000)
        eq(sprint.spacingM, 120, "ISSprOM 601: 30 mm at 1:4000"); eq(sprint.lineWidthMM, 0.18)
        eq(sprint.spacingPaperMM(scale: 4000), 30)
        XCTAssertTrue(NorthGrid.spacingPresetsM.contains(120))
    }
}
