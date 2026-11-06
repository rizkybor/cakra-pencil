#if DEBUG
import CakraCore
import MapKit
import QuartzCore
import UIKit

/// Uji performa otomatis (launch argument `-cp-perf`): menjalankan skenario berat dan mengukur frame yang
/// tersendat dengan CADisplayLink. Hasil ditulis ke Documents/perf.txt.
///
/// Budget PRD: pan/zoom ≥ 60 fps, tanpa frame drop > 50 ms. Di sini dihitung frame > 25 ms (lewat 1 frame 60 Hz)
/// dan > 50 ms (hitch) per skenario, plus waktu main thread untuk operasi model.
@MainActor
final class PerformanceProbe: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames: [Double] = []
    private var report: [String] = []
    /// Peta halaman Course (diisi MapCanvas role .course) untuk mengukur halaman Course Planner.
    static weak var courseMap: MKMapView?
    /// Total waktu MapCanvas.sync (semua peta) dan jumlah panggilannya, untuk memisahkan biaya peta vs panel.
    static var syncTime: Double = 0
    static var syncCount = 0

    func run(model: WorkspaceModel, map: MKMapView) async {
        report.append("\(AppInfo.name) perf — \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)")
        report.append("Objek: \(model.features.count), stroke: \(model.strokes.count), kontur: \(model.contourLines.count)")
        try? await Task.sleep(for: .seconds(2))

        // Data berat: 600 stroke × 40 titik dan 200 objek bezier tambahan di dalam frame.
        if let frame = model.frame {
            let t = CACurrentMediaTime()
            let c = frame.center
            for i in 0..<600 {
                let pts = (0..<40).map { j in Point2D(x: c.x - 300 + Double(i % 30) * 20 + Double(j) * 0.8, y: c.y - 400 + Double(i / 30) * 40 + sin(Double(j) / 4) * 3) }
                model.addStroke(points: pts)
            }
            report.append(String(format: "Tambah 600 stroke: %.0f ms main thread", (CACurrentMediaTime() - t) * 1000))
            let t2 = CACurrentMediaTime()
            model.editFeatures { list in
                for i in 0..<200 {
                    let o = Point2D(x: c.x - 300 + Double(i % 20) * 30, y: c.y + 100 + Double(i / 20) * 30)
                    list.append(Feature.rectangle(corners: [o, o + Point2D(x: 12, y: 0), o + Point2D(x: 12, y: -8), o + Point2D(x: 0, y: -8)],
                                                  colorHex: "#000000", widthMM: 0.14))
                }
            }
            report.append(String(format: "Tambah 200 objek: %.0f ms main thread", (CACurrentMediaTime() - t2) * 1000))
            try? await Task.sleep(for: .seconds(1))
        }

        await measure("Rotasi peta 360° (3 s)", seconds: 3) { p in
            let cam = map.camera.copy() as! MKMapCamera
            cam.heading = p * 360
            map.setCamera(cam, animated: false)
        }
        await measure("Pan peta (2 s)", seconds: 2) { p in
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
            await measure("Drag objek (2 s)", seconds: 2) { p in
                var moved = original
                moved.nodes = original.nodes.map { $0.moved(by: Point2D(x: sin(p * .pi * 2) * 20, y: p * 10)) }
                model.updateFeatureLive(moved)
            }
            model.commitFeatureEdit(from: before)
        }
        if model.dem != nil {
            let t = CACurrentMediaTime()
            for interval in [5.0, 2.5, 10.0] { model.updateContours { $0.intervalM = interval } }
            report.append(String(format: "3× ubah interval kontur: %.0f ms main thread", (CACurrentMediaTime() - t) * 1000))
            await measure("Hitung ulang kontur (2 s)", seconds: 2) { _ in }
        }

        await runCourses(model: model)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? report.joined(separator: "\n").write(to: docs.appendingPathComponent("perf.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Course Planner

    /// 60 kontrol + 6 lintasan × 14 kontrol: hitung (overprint, beban, pemeriksaan, PDF), lalu halaman Course:
    /// rotasi/pan/zoom, tarik kontrol, dan perubahan panel. Data lintasan dikembalikan seperti semula di akhir.
    private func runCourses(model: WorkspaceModel) async {
        guard let frame = model.frame else { return }
        let original = model.courseSet
        report.append("— Course Planner —")

        var t = CACurrentMediaTime()
        model.editCourses { set in
            set = CourseSet(eventTitle: "Uji Performa Lintasan")
            let e = frame.extent.insetBy(frame.widthM * 0.08)
            let start = ControlPoint(kind: .start, position: Point2D(x: e.minX + 20, y: e.minY + 20))
            let finish = ControlPoint(kind: .finish, position: Point2D(x: e.minX + 60, y: e.minY + 30))
            set.controls = [start, finish]
            for i in 0..<60 {
                let p = Point2D(x: e.minX + Double(i % 8) / 7 * e.width, y: e.minY + 60 + Double(i / 8) / 7 * (e.height - 60))
                set.controls.append(ControlPoint(kind: .control, code: set.nextFreeCode(), position: p,
                                                 description: ControlDescription(feature: ["2.4", "1.10", "5.11", "4.9"][i % 4], location: "11.1E")))
            }
            let controls = set.controls.filter { $0.kind == .control }
            for k in 0..<6 {
                let ids = (0..<14).map { controls[($0 * 5 + k * 7) % controls.count].id }
                set.courses.append(Course(name: "L\(k + 1)", controlIDs: [start.id] + ids + [finish.id], competitors: 40 + k * 10, climbM: 20 + k * 5))
            }
        }
        model.selectedCourseID = model.courseSet.courses.first?.id
        report.append(String(format: "Buat 60 kontrol + 6 lintasan: %.1f ms main thread", (CACurrentMediaTime() - t) * 1000))

        let set = model.courseSet
        t = CACurrentMediaTime()
        for c in set.courses { _ = CourseOverprint.make(set, course: c, sheet: model.project.sheet) }
        _ = CourseOverprint.make(set, course: nil, sheet: model.project.sheet)
        report.append(String(format: "Overprint 6 lintasan + semua kontrol: %.1f ms", (CACurrentMediaTime() - t) * 1000))
        t = CACurrentMediaTime()
        let warnings = set.warnings(), loads = set.controlLoads(), legs = set.sharedLegLoads()
        report.append(String(format: "Pemeriksaan + beban kontrol + leg bersama: %.1f ms (%d peringatan, %d kontrol, %d leg bersama)",
                             (CACurrentMediaTime() - t) * 1000, warnings.count, loads.count, legs.count))
        if let c = set.courses.first, let req = model.coursePDFRequest(for: c) {
            t = CACurrentMediaTime()
            let pdf = GeoPDFExporter.document(req)
            report.append(String(format: "PDF peta lomba 1 lintasan (%d objek peta): %.0f ms, %.1f MB",
                                 req.features.count, (CACurrentMediaTime() - t) * 1000, Double(pdf.count) / 1_048_576))
            t = CACurrentMediaTime()
            _ = IOFXMLExporter.courseData(set, frame: frame, sheet: model.project.sheet, zone: req.zone)
            report.append(String(format: "IOF XML 6 lintasan: %.1f ms", (CACurrentMediaTime() - t) * 1000))
        }

        // Halaman Course.
        t = CACurrentMediaTime()
        model.openCoursePlanner()
        while Self.courseMap == nil, CACurrentMediaTime() - t < 5 { try? await Task.sleep(for: .milliseconds(50)) }
        guard let map = Self.courseMap else {
            report.append("Halaman Course tidak terbuka")
            model.setCourses(original)
            return
        }
        report.append(String(format: "Buka halaman Course: %.0f ms", (CACurrentMediaTime() - t) * 1000))
        try? await Task.sleep(for: .seconds(2))

        await measure("Course: rotasi peta 360° (3 s)", seconds: 3) { p in
            let cam = map.camera.copy() as! MKMapCamera
            cam.heading = p * 360
            map.setCamera(cam, animated: false)
        }
        await measure("Course: pan peta (2 s)", seconds: 2) { p in
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
            await measure("Course: tarik kontrol (2 s)", seconds: 2) { p in
                model.moveControlLive(c.id, to: Point2D(x: c.position.x + sin(p * .pi * 2) * 40, y: c.position.y + p * 30))
            }
            model.commitCourseEdit(from: before)
        }
        if let course = model.selectedCourse {
            // Biaya model saja (tanpa render SwiftUI): 20 perubahan berturut-turut.
            let tm = CACurrentMediaTime()
            for _ in 0..<20 { model.updateCourse(course.id) { $0.competitors += 1 } }
            report.append(String(format: "Course: ubah data lintasan (model saja): %.2f ms per perubahan", (CACurrentMediaTime() - tm) * 1000 / 20))
            try? await Task.sleep(for: .seconds(1))
            Self.syncTime = 0
            Self.syncCount = 0
            await measure("Course: ubah panel tiap frame (peserta, 2 s)", seconds: 2) { _ in
                model.updateCourse(course.id) { $0.competitors += 1 }
            }
            report.append(String(format: "  di antaranya MapCanvas.sync: %d panggilan, total %.0f ms", Self.syncCount, Self.syncTime * 1000))
        }
        model.closeCoursePlanner()
        try? await Task.sleep(for: .seconds(1))
        model.setCourses(original)
        report.append("Data lintasan dikembalikan seperti semula.")
    }

    /// Jalankan `step(progress 0…1)` setiap frame selama `seconds`, catat durasi frame.
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
        report.append(String(format: "%@: %d frame, rata-rata %.1f ms (%.0f fps), terlambat >25 ms: %d, hitch >50 ms: %d, terburuk %.0f ms",
                             name, ms.count, avg, avg > 0 ? 1000 / avg : 0, slow, hitch, worst))
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 { frames.append(link.timestamp - last) }
        last = link.timestamp
    }
}
#endif
