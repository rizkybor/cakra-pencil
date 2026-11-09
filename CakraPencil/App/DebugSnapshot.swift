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
            let image = render(window)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? image.pngData()?.write(to: docs.appendingPathComponent("snapshot-\(name).png"))
            // The topmost sheet on its own (Mac Catalyst may keep it out of the window image).
            if var top = window.rootViewController?.presentedViewController {
                while let next = top.presentedViewController { top = next }
                let v: UIView = top.view
                let sheet = UIGraphicsImageRenderer(bounds: v.bounds).image { _ in
                    v.drawHierarchy(in: v.bounds, afterScreenUpdates: true)
                }
                try? sheet.pngData()?.write(to: docs.appendingPathComponent("snapshot-\(name)-sheet.png"))
            }
            // `-cp-snapshot-then <name2> <seconds>`: a second image afterwards (e.g. before/after a gesture).
            if let j = args.firstIndex(of: "-cp-snapshot-then"), j + 2 < args.count, let wait = Double(args[j + 2]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    let second = render(window)
                    try? second.pngData()?.write(to: docs.appendingPathComponent("snapshot-\(args[j + 1]).png"))
                    exit(0)
                }
                return
            }
            exit(0)
        }
    }

    /// The window plus the other visible windows of its scene (e.g. a sheet, which Mac Catalyst shows in its own
    /// window), drawn in window-level order at their positions.
    @MainActor private static func render(_ window: UIWindow) -> UIImage {
        let windows = (window.windowScene?.windows ?? [window]).filter { !$0.isHidden && $0.alpha > 0 }
            .sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            for w in windows {
                let origin = w.convert(CGPoint.zero, to: window)
                w.drawHierarchy(in: CGRect(origin: origin, size: w.bounds.size), afterScreenUpdates: true)
            }
        }
    }
}
#endif
