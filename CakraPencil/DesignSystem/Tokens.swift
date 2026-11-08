import SwiftUI
import UIKit

/// Design tokens from the PRD "Design System & UI Guidelines": pastel for chrome, strong for text/icons/status.
/// UI colors are never used as pen colors or map symbol colors.
enum CP {
    struct Tone {
        let fill: Color
        let strong: Color
    }

    static let paper = Color(light: 0xFAF7F2, dark: 0x1E1D1B)
    static let paper2 = Color(light: 0xF2EDE4, dark: 0x282623)
    static let line = Color(light: 0xE3DDD2, dark: 0x3A3733)
    static let ink = Color(light: 0x2B2A28, dark: 0xF1ECE4)
    static let inkMuted = Color(light: 0x6B665E, dark: 0xA8A196)

    static let sage = Tone(fill: Color(light: 0xD5E8D4, dark: 0x2F3D31), strong: Color(light: 0x3F6B4A, dark: 0xA8CFA9))
    static let peach = Tone(fill: Color(light: 0xF8DCCB, dark: 0x42302A), strong: Color(light: 0x8E4A2F, dark: 0xF0B79A))
    static let sky = Tone(fill: Color(light: 0xD6E6F5, dark: 0x2A3542), strong: Color(light: 0x315E85, dark: 0xA9C8E6))
    static let butter = Tone(fill: Color(light: 0xF7EBC0, dark: 0x3D3624), strong: Color(light: 0x735810, dark: 0xE8D48A))
    static let rose = Tone(fill: Color(light: 0xF5D0D3, dark: 0x432B2E), strong: Color(light: 0x933340, dark: 0xEBA6AD))

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 6
        /// Chips, pills and segmented controls: a modest rounding, not a full capsule.
        static let chip: CGFloat = 7
        static let panel: CGFloat = 10
    }

    /// Desk Mode hit target; Field Mode (56 pt) comes later. Mac (mouse/trackpad): more compact.
    #if targetEnvironment(macCatalyst)
    static let hitTarget: CGFloat = 36
    #else
    static let hitTarget: CGFloat = 44
    #endif

    /// Running as a Mac app (Mac Catalyst).
    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// Technical numbers (coordinates, mm, dpi) use SF Mono with tabular digits.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: fs(size), weight: weight, design: .monospaced).monospacedDigit()
    }

    /// Font size: iPad as is; Mac smaller, like Mac apps (13 → 11, 15 → 13, 17 → 15; min 10 pt).
    static func fs(_ size: CGFloat) -> CGFloat {
        #if targetEnvironment(macCatalyst)
        return max(10, size <= 12 ? size - 1 : (size * 0.86).rounded())
        #else
        return size
        #endif
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    init(hexString: String) {
        self.init(uiColor: UIColor(hexString: hexString))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// "#RRGGBB" from the color (sRGB components, alpha ignored).
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let c = [r, g, b].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c[0], c[1], c[2])
    }

    convenience init(hexString: String) {
        var s = hexString
        if s.hasPrefix("#") { s.removeFirst() }
        self.init(hex: UInt32(s, radix: 16) ?? 0)
    }
}

/// Opaque paper panel with a hairline border; a subtle shadow only for floating panels.
struct PanelStyle: ViewModifier {
    var floating = true

    func body(content: Content) -> some View {
        content
            .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(CP.line, lineWidth: 1))
            .shadow(color: .black.opacity(floating ? 0.08 : 0), radius: 1, y: 1)
    }
}

extension View {
    func cpPanel(floating: Bool = true) -> some View { modifier(PanelStyle(floating: floating)) }
}

/// 44 × 44 pt tool button; active = sage fill + 1.5 px strong border.
struct ToolButtonStyle: ButtonStyle {
    var isActive = false
    /// Top bar size (undo, redo, panel, save): same height as the Export button. The tool rail keeps the full size.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let side = compact ? (CP.isMac ? 28 : 36) : CP.hitTarget
        configuration.label
            .font(.system(size: CP.fs(compact ? 15 : 18), weight: .regular))
            .foregroundStyle(isActive ? CP.sage.strong : CP.ink)
            .frame(width: side, height: side)
            .background(isActive ? CP.sage.fill : (configuration.isPressed ? CP.paper2 : .clear),
                        in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control)
                .strokeBorder(isActive ? CP.sage.strong.opacity(compact ? 0.6 : 1) : .clear, lineWidth: compact ? 1 : 1.5))
            .contentShape(Rectangle())
    }
}

/// Primary button: sage fill, strong text.
struct PrimaryButtonStyle: ButtonStyle {
    /// Smaller version for top bars (Export), in line with the toolbar icons.
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: CP.fs(compact ? 14 : 15), weight: .semibold))
            .foregroundStyle(isEnabled ? CP.sage.strong : CP.inkMuted)
            .padding(.horizontal, compact ? CP.Space.m : CP.Space.l)
            .frame(minHeight: compact ? (CP.isMac ? 28 : 36) : CP.hitTarget)
            .background(isEnabled ? CP.sage.fill : CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control)
                .strokeBorder(isEnabled ? CP.sage.strong.opacity(configuration.isPressed ? 1 : 0.4) : CP.line, lineWidth: 1))
    }
}

/// Secondary button: solid paper background + border (the contour motif behind doesn't show through).
struct SecondaryButtonStyle: ButtonStyle {
    /// Smaller version, same size as `PrimaryButtonStyle(compact: true)`.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: CP.fs(compact ? 14 : 15), weight: .medium))
            .foregroundStyle(CP.ink)
            .padding(.horizontal, compact ? CP.Space.m : CP.Space.l)
            .frame(minHeight: compact ? (CP.isMac ? 28 : 36) : CP.hitTarget)
            .background(configuration.isPressed ? CP.paper2 : CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line, lineWidth: 1))
    }
}

/// Thin contour lines for empty states (a cartographic identity, not a generic illustration).
struct ContourMotif: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 1...7 {
                let r = CGFloat(i) * min(size.width, size.height) / 16
                var path = Path()
                for step in 0...72 {
                    let t = CGFloat(step) / 72 * 2 * .pi
                    let wobble = 1 + 0.08 * sin(3 * t + CGFloat(i)) + 0.05 * cos(5 * t)
                    let p = CGPoint(x: c.x + cos(t) * r * 1.3 * wobble, y: c.y + sin(t) * r * wobble)
                    step == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                ctx.stroke(path, with: .color(CP.inkMuted.opacity(i % 5 == 0 ? 0.5 : 0.25)), lineWidth: i % 5 == 0 ? 1.2 : 0.7)
            }
        }
        .accessibilityHidden(true)
    }
}
