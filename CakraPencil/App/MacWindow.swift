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
}
