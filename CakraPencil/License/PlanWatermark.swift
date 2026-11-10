import CakraCore
import Combine
import SwiftUI
import UIKit

/// Small "STARTER" / "TRIAL" label in the bottom-left corner of every screen (sheets included), on iPad and Mac.
/// Paid plans (Professional, Lifetime, Organization) show nothing; an iPad without a license has the view-only
/// banner instead. It sits in its own window above the app and never takes touches or clicks.
@MainActor
enum PlanWatermark {
    private static var windows: [ObjectIdentifier: UIWindow] = [:]
    private static var planObserver: AnyCancellable?

    /// "STARTER" (Mac) or "TRIAL"; nil on paid plans and on an iPad without a license.
    static func label(for plan: LicenseManager.Plan) -> String? {
        switch plan {
        case .trial: "TRIAL"
        case .starter: LicenseManager.requiresKey ? nil : "STARTER"
        default: nil
        }
    }

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
            window.isHidden = label(for: LicenseManager.shared.plan) == nil
            windows[id] = window
        }
        // Paid plans: the label window is hidden altogether (no extra layer over the app).
        planObserver = planObserver ?? LicenseManager.shared.$plan.removeDuplicates().sink { plan in
            let hidden = label(for: plan) == nil
            for window in windows.values { window.isHidden = hidden }
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

    /// Second line: what to do (Starter) or when the trial ends.
    private var detail: String {
        if license.plan == .trial {
            if let end = license.payload?.expiresAt {
                return "Trial ends \(end.formatted(date: .long, time: .omitted))."
            }
            return "Activate a license key to keep every feature."
        }
        return "Activate a license key to unlock every feature."
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            // Starter on the Mac and Trial: plain see-through text in the corner, like an OS activation notice.
            if PlanWatermark.label(for: license.plan) != nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(AppInfo.name) \(license.plan.title)")
                        .font(.system(size: CP.fs(17)))
                    Text(detail)
                        .font(.system(size: CP.fs(12)))
                }
                .foregroundStyle(CP.ink.opacity(0.32))
                .lineLimit(1)
                .padding(.leading, 32)
                .padding(.bottom, CP.isMac ? 30 : 24)
            }
        }
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
