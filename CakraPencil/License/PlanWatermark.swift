import SwiftUI
import UIKit

/// Small "STARTER" / "TRIAL" label in the bottom-left corner of every screen (sheets included), on iPad and Mac.
/// Paid plans (Professional, Lifetime, Organization) show nothing; an iPad without a license has the view-only
/// banner instead. It sits in its own window above the app and never takes touches or clicks.
@MainActor
enum PlanWatermark {
    private static var windows: [ObjectIdentifier: UIWindow] = [:]

    /// Adds the label window to every open window scene (once per scene).
    static func install() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            let id = ObjectIdentifier(scene)
            guard windows[id] == nil else { continue }
            let window = PassthroughWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.backgroundColor = .clear
            let host = UIHostingController(rootView: PlanWatermarkView(license: .shared))
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window.overrideUserInterfaceStyle = AppearanceMode.current.interfaceStyle
            window.isHidden = false
            windows[id] = window
        }
    }
}

/// A window that lets every touch and click through to the windows below.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override var canBecomeKey: Bool { false }
}

struct PlanWatermarkView: View {
    @ObservedObject var license: LicenseManager

    /// Starter on the Mac and Trial show the label; paid plans and the unlicensed iPad don't.
    private var text: String? {
        switch license.plan {
        case .trial: "TRIAL"
        case .starter: LicenseManager.requiresKey ? nil : "STARTER"
        default: nil
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            if let text {
                Text(text)
                    .font(.system(size: CP.fs(10), weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(CP.inkMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(CP.paper.opacity(0.75), in: Capsule())
                    .overlay(Capsule().strokeBorder(CP.line, lineWidth: 0.5))
                    .opacity(0.85)
                    .padding(.leading, CP.Space.m)
                    .padding(.bottom, CP.isMac ? CP.Space.s : CP.Space.xs)
            }
        }
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
