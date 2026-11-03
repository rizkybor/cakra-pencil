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

    func run(model: WorkspaceModel, map: MKMapView) async {
        report.append("Cakra Pencil perf — \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)")
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

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? report.joined(separator: "\n").write(to: docs.appendingPathComponent("perf.txt"), atomically: true, encoding: .utf8)
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
