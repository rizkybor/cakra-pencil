import UIKit

/// Jendela Mac (Mac Catalyst): judul jendela disembunyikan (nama proyek sudah ada di bar atas aplikasi),
/// tanpa garis pemisah, dan ukuran minimum agar rail, panel, dan bar bawah tidak bertumpuk.
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
