#if DEBUG
import UIKit

/// `-cp-snapshot <nama>`: setelah `-cp-snapshot-delay` detik (default 5), simpan gambar jendela ke
/// Documents/snapshot-<nama>.png lalu keluar. Untuk memeriksa tata letak (mis. Mac Catalyst) tanpa izin
/// rekam layar.
enum DebugSnapshot {
    @MainActor static func scheduleIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-cp-snapshot"), i + 1 < args.count else { return }
        let name = args[i + 1]
        let delay = args.firstIndex(of: "-cp-snapshot-delay").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { exit(1) }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? image.pngData()?.write(to: docs.appendingPathComponent("snapshot-\(name).png"))
            // `-cp-snapshot-then <nama2> <detik>`: gambar kedua sesudahnya (mis. sebelum/sesudah gestur).
            if let j = args.firstIndex(of: "-cp-snapshot-then"), j + 2 < args.count, let wait = Double(args[j + 2]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    let second = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    try? second.pngData()?.write(to: docs.appendingPathComponent("snapshot-\(args[j + 1]).png"))
                    exit(0)
                }
                return
            }
            exit(0)
        }
    }
}
#endif
