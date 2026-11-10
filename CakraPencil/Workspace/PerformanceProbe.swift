#if DEBUG
import CakraCore
import MapKit
import QuartzCore
import UIKit

/// Automated performance test (launch argument `-cp-perf`): runs heavy scenarios and measures stuttering
/// frames with CADisplayLink. Results are written to Documents/perf.txt.
///
/// PRD budget: pan/zoom ≥ 60 fps, no frame drop > 50 ms. Here we count frames > 25 ms (missed one 60 Hz frame)
/// and > 50 ms (hitch) per scenario, plus main-thread time for model operations.
@MainActor
final class PerformanceProbe: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames: [Double] = []
    private var report: [String] = []
    /// Course page map (set by MapCanvas role .course) for measuring the Course Planner page.
    static weak var courseMap: MKMapView?
    /// Total MapCanvas.sync time (all maps) and its call count, to separate map cost from panel cost.
    static var syncTime: Double = 0
    static var syncCount = 0

    func run(model: WorkspaceModel, map: MKMapView) async {
        report.append("\(AppInfo.name) perf — \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)")
        report.append("Objects: \(model.features.count), strokes: \(model.strokes.count), contours: \(model.contourLines.count)")
        try? await Task.sleep(for: .seconds(2))

        // Heavy data: 600 strokes × 40 points and 200 extra bezier objects inside the frame.
        if let frame = model.frame {
            let t = CACurrentMediaTime()
            let c = frame.center
            for i in 0..<600 {
                let pts = (0..<40).map { j in Point2D(x: c.x - 300 + Double(i % 30) * 20 + Double(j) * 0.8, y: c.y - 400 + Double(i / 30) * 40 + sin(Double(j) / 4) * 3) }
                model.addStroke(points: pts)
            }
            report.append(String(format: "Add 600 strokes: %.0f ms main thread", (CACurrentMediaTime() - t) * 1000))
            let t2 = CACurrentMediaTime()
            model.editFeatures { list in
                for i in 0..<200 {
                    let o = Point2D(x: c.x - 300 + Double(i % 20) * 30, y: c.y + 100 + Double(i / 20) * 30)
                    list.append(Feature.rectangle(corners: [o, o + Point2D(x: 12, y: 0), o + Point2D(x: 12, y: -8), o + Point2D(x: 0, y: -8)],
                                                  colorHex: "#000000", widthMM: 0.14))
                }
            }
            report.append(String(format: "Add 200 objects: %.0f ms main thread", (CACurrentMediaTime() - t2) * 1000))
            try? await Task.sleep(for: .seconds(1))
        }

        await measure("Map rotation 360° (3 s)", seconds: 3) { p in
            let cam = map.camera.copy() as! MKMapCamera
            cam.heading = p * 360
            map.setCamera(cam, animated: false)
        }
        await measure("Map pan (2 s)", seconds: 2) { p in
            let b = map.bounds
            let target = CGPoint(x: b.midX + CGFloat(sin(p * .pi * 2)) * 3, y: b.midY + 2)
            map.setCenter(map.convert(target, toCoordinateFrom: map), animated: false)
        }
        await measure("Zoom in/out (2 s)", seconds: 2) { p in
            let cam = map.camera.copy() as! MKMapCamera
            cam.centerCoordinateDistance *= p < 0.5 ? 0.985 : 1 / 0.985
            map.setCamera(cam, animated: false)
        }
        if let f = model.features.last {
            model.selectedFeatureID = f.id
            let original = f
            let before = model.features
            await measure("Object drag (2 s)", seconds: 2) { p in
                var moved = original
                moved.nodes = original.nodes.map { $0.moved(by: Point2D(x: sin(p * .pi * 2) * 20, y: p * 10)) }
                model.updateFeatureLive(moved)
            }
            model.commitFeatureEdit(from: before)
        }
        if model.dem != nil {
            let t = CACurrentMediaTime()
            for interval in [5.0, 2.5, 10.0] { model.updateContours { $0.intervalM = interval } }
            report.append(String(format: "3× change contour interval: %.0f ms main thread", (CACurrentMediaTime() - t) * 1000))
            await measure("Contour regeneration (2 s)", seconds: 2) { _ in }
        }

        await runCourses(model: model)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? report.joined(separator: "\n").write(to: docs.appendingPathComponent("perf.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Course Planner

    /// 60 controls + 6 courses × 14 controls: compute (overprint, load, checks, PDF), then the Course page:
    /// rotate/pan/zoom, drag a control, and panel changes. Course data is restored to its original state at the end.
    private func runCourses(model: WorkspaceModel) async {
        guard let frame = model.frame else { return }
        let original = model.courseSet
        report.append("— Course Planner —")

        var t = CACurrentMediaTime()
        model.editCourses { set in
            set = CourseSet(eventTitle: "Course Performance Test")
            let e = frame.extent.insetBy(frame.widthM * 0.08)
            let start = ControlPoint(kind: .start, position: Point2D(x: e.minX + 20, y: e.minY + 20))
            let finish = ControlPoint(kind: .finish, position: Point2D(x: e.minX + 60, y: e.minY + 30))
            set.controls = [start, finish]
            for i in 0..<60 {
                let p = Point2D(x: e.minX + Double(i % 8) / 7 * e.width, y: e.minY + 60 + Double(i / 8) / 7 * (e.height - 60))
                set.controls.append(ControlPoint(kind: .control, code: set.nextFreeCode(), position: p,
                                                 description: ControlDescription(feature: ["2.4", "1.10", "5.11", "4.9"][i % 4], location: "12.1E")))
            }
            let controls = set.controls.filter { $0.kind == .control }
            for k in 0..<6 {
                let ids = (0..<14).map { controls[($0 * 5 + k * 7) % controls.count].id }
                set.courses.append(Course(name: "L\(k + 1)", controlIDs: [start.id] + ids + [finish.id], competitors: 40 + k * 10, climbM: 20 + k * 5))
            }
        }
        model.selectedCourseID = model.courseSet.courses.first?.id
        report.append(String(format: "Create 60 controls + 6 courses: %.1f ms main thread", (CACurrentMediaTime() - t) * 1000))

        let set = model.courseSet
        t = CACurrentMediaTime()
        for c in set.courses { _ = CourseOverprint.make(set, course: c, sheet: model.project.sheet) }
        _ = CourseOverprint.make(set, course: nil, sheet: model.project.sheet)
        report.append(String(format: "Overprint 6 courses + all controls: %.1f ms", (CACurrentMediaTime() - t) * 1000))
        t = CACurrentMediaTime()
        let warnings = set.warnings(), loads = set.controlLoads(), legs = set.sharedLegLoads()
        report.append(String(format: "Checks + control load + shared legs: %.1f ms (%d warnings, %d controls, %d shared legs)",
                             (CACurrentMediaTime() - t) * 1000, warnings.count, loads.count, legs.count))
        if let c = set.courses.first, let req = model.coursePDFRequest(for: c) {
            t = CACurrentMediaTime()
            let pdf = GeoPDFExporter.document(req)
            report.append(String(format: "Race map PDF 1 course (%d map objects): %.0f ms, %.1f MB",
                                 req.features.count, (CACurrentMediaTime() - t) * 1000, Double(pdf.count) / 1_048_576))
            t = CACurrentMediaTime()
            _ = IOFXMLExporter.courseData(set, frame: frame, sheet: model.project.sheet, zone: req.zone)
            report.append(String(format: "IOF XML 6 courses: %.1f ms", (CACurrentMediaTime() - t) * 1000))
        }

        // Course page.
        t = CACurrentMediaTime()
        model.openCoursePlanner()
        while Self.courseMap == nil, CACurrentMediaTime() - t < 5 { try? await Task.sleep(for: .milliseconds(50)) }
        guard let map = Self.courseMap else {
            report.append("Course page did not open")
            model.setCourses(original)
            return
        }
        report.append(String(format: "Open Course page: %.0f ms", (CACurrentMediaTime() - t) * 1000))
        try? await Task.sleep(for: .seconds(2))

        await measure("Course: map rotation 360° (3 s)", seconds: 3) { p in
            let cam = map.camera.copy() as! MKMapCamera
            cam.heading = p * 360
            map.setCamera(cam, animated: false)
        }
        await measure("Course: map pan (2 s)", seconds: 2) { p in
            let b = map.bounds
            map.setCenter(map.convert(CGPoint(x: b.midX + CGFloat(sin(p * .pi * 2)) * 3, y: b.midY + 2), toCoordinateFrom: map), animated: false)
        }
        await measure("Course: zoom in/out (2 s)", seconds: 2) { p in
            let cam = map.camera.copy() as! MKMapCamera
            cam.centerCoordinateDistance *= p < 0.5 ? 0.985 : 1 / 0.985
            map.setCamera(cam, animated: false)
        }
        if let c = model.courseSet.controls.first(where: { $0.kind == .control }) {
            let before = model.courseSet
            model.selectedControlID = c.id
            await measure("Course: drag control (2 s)", seconds: 2) { p in
                model.moveControlLive(c.id, to: Point2D(x: c.position.x + sin(p * .pi * 2) * 40, y: c.position.y + p * 30))
            }
            model.commitCourseEdit(from: before)
        }
        if let course = model.selectedCourse {
            // Model cost only (no SwiftUI rendering): 20 consecutive changes.
            let tm = CACurrentMediaTime()
            for _ in 0..<20 { model.updateCourse(course.id) { $0.competitors += 1 } }
            report.append(String(format: "Course: change course data (model only): %.2f ms per change", (CACurrentMediaTime() - tm) * 1000 / 20))
            try? await Task.sleep(for: .seconds(1))
            Self.syncTime = 0
            Self.syncCount = 0
            await measure("Course: change panel every frame (competitors, 2 s)", seconds: 2) { _ in
                model.updateCourse(course.id) { $0.competitors += 1 }
            }
            report.append(String(format: "  of which MapCanvas.sync: %d calls, total %.0f ms", Self.syncCount, Self.syncTime * 1000))
        }
        model.closeCoursePlanner()
        try? await Task.sleep(for: .seconds(1))
        model.setCourses(original)
        report.append("Course data restored to original.")
    }

    /// Run `step(progress 0…1)` every frame for `seconds`, recording frame durations.
    private func measure(_ name: String, seconds: Double, step: @escaping (Double) -> Void) async {
        frames = []
        last = 0
        let start = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        while CACurrentMediaTime() - start < seconds {
            step((CACurrentMediaTime() - start) / seconds)
            try? await Task.sleep(for: .milliseconds(8))
        }
        link.invalidate()
        let ms = frames.map { $0 * 1000 }
        let slow = ms.filter { $0 > 25 }.count, hitch = ms.filter { $0 > 50 }.count
        let avg = ms.isEmpty ? 0 : ms.reduce(0, +) / Double(ms.count)
        let worst = ms.max() ?? 0
        report.append(String(format: "%@: %d frames, average %.1f ms (%.0f fps), late >25 ms: %d, hitch >50 ms: %d, worst %.0f ms",
                             name, ms.count, avg, avg > 0 ? 1000 / avg : 0, slow, hitch, worst))
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 { frames.append(link.timestamp - last) }
        last = link.timestamp
    }
}
#endif
