import CakraCore
import SwiftUI

/// Splash screen shown when OCCA opens: warm paper background with contour lines that fade in, the logo settling in,
/// an orange pen stroke drawing itself under the name, the tagline, and the supporter credit. About 4 s, then it
/// fades out to the project list. Light and dark mode; same on iPad and Mac (sizes scale with the window).
struct SplashView: View {
    /// "Version 0.1.0 (1)" from the bundle.
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    @Environment(\.colorScheme) private var scheme
    @State private var contours = false
    @State private var logo = false
    @State private var stroke: CGFloat = 0
    @State private var text = false

    /// Solid paper colour (no gradient), the same as the app's background.
    private var background: Color { CP.paper }

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height)
            ZStack {
                background.ignoresSafeArea()
                SplashContours(color: scheme == .dark ? Color(hexString: "#C9A46A") : Color(hexString: "#B58A52"))
                    .opacity(contours ? (scheme == .dark ? 0.20 : 0.26) : 0)
                    .scaleEffect(contours ? 1 : 1.06)
                    .ignoresSafeArea()

                VStack(spacing: unit * 0.035) {
                    Image("AppLogo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: unit * 0.30, height: unit * 0.30)
                        .clipShape(RoundedRectangle(cornerRadius: unit * 0.30 * 0.2237, style: .continuous))
                        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.14), radius: unit * 0.03, y: unit * 0.015)
                        .scaleEffect(logo ? 1 : 0.86)
                        .opacity(logo ? 1 : 0)

                    VStack(spacing: unit * 0.014) {
                        Text(AppInfo.name)
                            .font(.system(size: unit * 0.075, weight: .semibold))
                            .tracking(unit * 0.012)
                            .foregroundStyle(scheme == .dark ? Color.white : Color(hexString: "#1E201F"))
                        PenStroke()
                            .trim(from: 0, to: stroke)
                            .stroke(Color(hexString: "#F07E14"), style: StrokeStyle(lineWidth: max(2, unit * 0.006), lineCap: .round))
                            .frame(width: unit * 0.30, height: unit * 0.025)
                        Text(AppInfo.fullName.uppercased())
                            .font(.system(size: max(12, unit * 0.024), weight: .medium))
                            .tracking(unit * 0.006)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(scheme == .dark ? Color.white.opacity(0.6) : Color(hexString: "#6B665E"))
                            .padding(.top, unit * 0.008)
                    }
                    .opacity(text ? 1 : 0)
                    .offset(y: text ? 0 : unit * 0.015)
                }
                .offset(y: -unit * 0.03)

                VStack(spacing: 6) {
                    Spacer()
                    Text(Self.version)
                        .font(.system(size: max(11, unit * 0.016), weight: .medium, design: .monospaced))
                        .foregroundStyle(scheme == .dark ? Color.white.opacity(0.55) : Color(hexString: "#8A847A"))
                        .accessibilityIdentifier("splashVersion")
                        .padding(.bottom, max(10, unit * 0.022))
                    Text("Supported by")
                        .font(.system(size: max(10, unit * 0.014), weight: .medium))
                        .foregroundStyle(scheme == .dark ? Color.white.opacity(0.5) : Color(hexString: "#8A847A"))
                    Image("JCDLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: max(18, unit * 0.032))
                }
                .padding(.bottom, max(28, geo.safeAreaInsets.bottom + unit * 0.05))
                .opacity(text ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(AppInfo.name), \(AppInfo.fullName). \(Self.version). Supported by \(AppInfo.supporter).")
        .accessibilityIdentifier("splashScreen")
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) { contours = true }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(0.15)) { logo = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.55)) { text = true }
            // The pen stroke draws slowly and finishes at 3.5 s (0.75 s delay + 2.75 s).
            withAnimation(.easeInOut(duration: 2.75).delay(0.75)) { stroke = 1 }
        }
    }
}

/// The OCCA pen stroke: a gentle arc, like the curve on the logo's flag.
private struct PenStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.75))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.75), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.2))
        return p
    }
}

/// Map-like contour lines: two hills, smooth nested rings, every 5th an index contour.
private struct SplashContours: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let u = max(size.width, size.height)
            for (cx, cy, rings, base, seed) in [(0.90, 0.10, 9, 0.032, 1.0), (0.08, 0.92, 8, 0.034, 2.3)] as [(CGFloat, CGFloat, Int, CGFloat, CGFloat)] {
                let c = CGPoint(x: size.width * cx, y: size.height * cy)
                for i in 1...rings {
                    let r = CGFloat(i) * u * base
                    var path = Path()
                    for step in 0...120 {
                        let t = CGFloat(step) / 120 * 2 * .pi
                        let wobble = 1 + 0.09 * sin(3 * t + seed) + 0.05 * cos(5 * t + seed * 2) + 0.03 * sin(2 * t)
                        let p = CGPoint(x: c.x + cos(t) * r * 1.2 * wobble, y: c.y + sin(t) * r * wobble)
                        step == 0 ? path.move(to: p) : path.addLine(to: p)
                    }
                    path.closeSubpath()
                    let index = i % 5 == 0
                    ctx.stroke(path, with: .color(color.opacity(index ? 1 : 0.55)), lineWidth: index ? 1.4 : 0.8)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Root wrapper: the splash on top of the app every time OCCA opens (about 4 s), then a fade.
/// DEBUG: `-cp-splash-hold` keeps it on screen (screenshots); `-cp-no-splash` skips it (UI tests).
struct SplashContainer<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var showsSplash: Bool = {
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains("-cp-no-splash")
        #else
        return true
        #endif
    }()

    var body: some View {
        ZStack {
            content
            if showsSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-cp-splash-hold") { return }
            #endif
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeInOut(duration: 0.6)) { showsSplash = false }
        }
    }
}
