import UIKit

/// Mac window (Mac Catalyst): the window title is hidden (the project name is already in the app's top bar),
/// no separator line, and a minimum size so the rail, panels, and bottom bar don't overlap.
enum MacWindow {
    @MainActor static func configure() {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            if let bar = scene.titlebar {
                bar.titleVisibility = .hidden
                bar.toolbar = nil
                bar.separatorStyle = .none
            }
            scene.sizeRestrictions?.minimumSize = CGSize(width: 1100, height: 760)
        }
        #endif
    }

    /// Quit the app (Mac only, like ⌘Q / OCCA → Quit). iPadOS apps must not quit themselves (App Store rule), so this
    /// does nothing there. Mac Catalyst has no UIKit quit API: AppKit's NSApplication.terminate(_:) is used.
    @MainActor static func quit() {
        #if targetEnvironment(macCatalyst)
        if let appClass = NSClassFromString("NSApplication") as? NSObject.Type,
           let app = appClass.value(forKey: "sharedApplication") as? NSObject,
           app.responds(to: NSSelectorFromString("terminate:")) {
            app.perform(NSSelectorFromString("terminate:"), with: nil)
            return
        }
        // Fallback: close every window.
        for session in UIApplication.shared.openSessions {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
        }
        #endif
    }
}
