#if DEBUG
import UIKit

/// `-cp-snapshot <name>`: after `-cp-snapshot-delay` seconds (default 5), save an image of the window to
/// Documents/snapshot-<name>.png and quit. For checking the layout (e.g. Mac Catalyst) without screen
/// recording permission.
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
            // `-cp-snapshot-then <name2> <seconds>`: a second image afterwards (e.g. before/after a gesture).
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
