#if DEBUG
import Foundation

/// UI tests: `-cp-restore-fixtures` replaces each project in Documents/Projects with its clean copy from
/// Documents/Fixtures (same package name) before the app loads, so every test starts from the same objects and
/// courses — leftovers of an earlier (failed) test can't merge with new strokes. No Fixtures folder = no-op.
enum DebugFixtures {
    static func restoreIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-cp-restore-fixtures") else { return }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fixtures = docs.appendingPathComponent("Fixtures", isDirectory: true)
        let projects = docs.appendingPathComponent("Projects", isDirectory: true)
        guard let names = try? fm.contentsOfDirectory(atPath: fixtures.path) else { return }
        for name in names where name.hasSuffix(".cakra") {
            let target = projects.appendingPathComponent(name)
            // Keep the downloaded per-device HD imagery (not part of the fixture).
            let imagery = target.appendingPathComponent("imagery")
            let keep = docs.appendingPathComponent(".fixture-imagery-\(name)")
            try? fm.removeItem(at: keep)
            if fm.fileExists(atPath: imagery.path) { try? fm.moveItem(at: imagery, to: keep) }
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: fixtures.appendingPathComponent(name), to: target)
            if fm.fileExists(atPath: keep.path) {
                try? fm.removeItem(at: target.appendingPathComponent("imagery"))
                try? fm.moveItem(at: keep, to: target.appendingPathComponent("imagery"))
            }
        }
    }
}
#endif
