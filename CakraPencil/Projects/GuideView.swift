import CakraCore
import SwiftUI

/// Short guide for new users: what OCCA does, starting a project, drawing, fieldwork on iPad, moving work between iPad
/// and Mac, and processing / sharing. Shown once per device on first launch (there is no account, so "new" means new on
/// this device), and any time from the Guide button on the project list or Help › OCCA Guide on Mac.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    /// Seen on this device (the guide opens by itself until then).
    static let seenKey = "guideSeen.v1"

    /// Open by itself on first launch. DEBUG launches with test / screenshot arguments (`-cp-…`) skip it, unless
    /// `-cp-show-guide` asks for it.
    static var shouldOpenAutomatically: Bool {
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        if args.contains("-cp-show-guide") { return true }
        if args.contains(where: { $0.hasPrefix("-cp-") }) { return false }
        #endif
        return !UserDefaults.standard.bool(forKey: seenKey)
    }

    private var pages: [GuidePage] { GuidePage.all }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Guide").font(.system(size: CP.fs(13), weight: .semibold)).foregroundStyle(CP.inkMuted)
                    .accessibilityHidden(true)
                Spacer()
                if page < pages.count - 1 {
                    Button("Skip") { finish() }
                        .accessibilityIdentifier("guideSkip")
                }
            }
            .padding(.horizontal, CP.Space.xl)
            .padding(.top, CP.Space.l)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    GuidePageView(page: pages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            // Page dots.
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule().fill(i == page ? Color(hexString: "#E8760F") : CP.line)
                        .frame(width: i == page ? 20 : 7, height: 7)
                        .onTapGesture { withAnimation { page = i } }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(page + 1) of \(pages.count)")
            .padding(.bottom, CP.Space.m)

            HStack(spacing: CP.Space.m) {
                if page > 0 {
                    Button { withAnimation { page -= 1 } } label: { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .accessibilityIdentifier("guideBack")
                }
                Spacer()
                if page < pages.count - 1 {
                    Button { withAnimation { page += 1 } } label: { Label("Next", systemImage: "chevron.right").labelStyle(TrailingIconLabel()) }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .accessibilityIdentifier("guideNext")
                } else {
                    Button { finish() } label: { Label("Start mapping", systemImage: "pencil.and.outline") }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("guideDone")
                }
            }
            .padding(.horizontal, CP.Space.xl)
            .padding(.bottom, CP.Space.xl)
        }
        .background(CP.paper)
        .frame(minWidth: CP.isMac ? 620 : nil, minHeight: CP.isMac ? 640 : nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guide")
        .onDisappear { UserDefaults.standard.set(true, forKey: Self.seenKey) }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        dismiss()
    }
}

private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

struct GuidePage {
    /// Screenshot in the asset catalog (taken from the app).
    var image: String
    var icon: String
    var tint: Color
    var title: String
    var subtitle: String
    var points: [(icon: String, text: String)]
    /// Something that depends on this device (Mac, Wi-Fi-only iPad).
    var deviceNote: String? = nil

    static var all: [GuidePage] {
        let mac = CP.isMac
        let wifiOnly = !mac && !DeviceCapabilities.canRecordTracks
        return [
            GuidePage(image: "GuideWelcome", icon: "map", tint: Color(hexString: "#E8760F"), title: "Welcome to \(AppInfo.name)",
                      subtitle: "Draw orienteering maps to the IOF standards — ISOM 2017-2 for forest, ISSprOM 2019-2 for sprint — on iPad and Mac.",
                      points: [
                        ("globe.asia.australia", "HD satellite imagery and contours as the base to draw on, saved for offline use."),
                        ("square.grid.3x3", "Symbols from OCCA's own sets, OCAD (.ocd) and OpenOrienteering (.omap)."),
                        ("figure.walk", "Fieldwork on iPad, careful drawing at the desk on Mac — or both on one iPad."),
                        ("flag.2.crossed", "Courses, PDF and image export, OCAD / OOM files."),
                      ]),
            GuidePage(image: "GuideProject", icon: "plus.rectangle.on.rectangle", tint: Color(hexString: "#315E85"), title: "Start a project",
                      subtitle: "One project = one map: its area, scale and everything drawn on it.",
                      points: [
                        ("plus", "New project: search the place, move the frame over the area, choose the scale (1:4000 sprint, 1:10000 / 1:15000 forest) and paper."),
                        ("lock", "Lock the area. The map tab downloads HD imagery for it; the Contours tab adds elevation lines."),
                        ("folder", "Open file brings in a .occa project, or an OCAD / OOM map as a new project."),
                      ]),
            GuidePage(image: "GuideDraw", icon: "pencil.tip", tint: Color(hexString: "#3F6B4A"), title: "Draw the map",
                      subtitle: mac ? "Draw with the mouse or trackpad; every tool has a keyboard shortcut." : "Draw with Apple Pencil; your finger moves the map.",
                      points: [
                        ("square.grid.3x3", "Symbols tab: pick a symbol — points are tapped, lines and areas drawn with the pen tool."),
                        ("cursorarrow", "Select and node tools move, reshape, cut and join objects; undo is always there."),
                        ("square.3.layers.3d", "Layers tab: everything you drew, with show / hide. Patterns, tags and colours follow the IOF standard."),
                        ("pencil.and.scribble", "The sketch pencil is for quick notes on the map, not printed as symbols."),
                      ]),
            GuidePage(image: "GuideField", icon: "figure.walk.motion", tint: Color(hexString: "#8E4A2F"), title: "Fieldwork on iPad",
                      subtitle: "Field tab › capture tools, or Field mode with big buttons and a touch lock.",
                      points: [
                        ("checklist", "Ready check before you leave: imagery, contours, battery, storage — the map works without signal."),
                        ("record.circle", "Record the tracks you walk (iPad Wi-Fi + Cellular, which has a GPS chip)."),
                        ("mappin.and.ellipse", "Notes with photos, a bearing / distance offset, quick vegetation classes and averaged positions."),
                        ("pencil.tip.crop.circle", "Mark up a photo with Apple Pencil: circle the boulder, draw the fence."),
                      ],
                      deviceNote: mac ? "This Mac has no GPS: fieldwork is captured on iPad and imported here (next page)."
                          : wifiOnly ? "This iPad has no GPS chip (Wi-Fi only), so track recording isn't shown. Notes, photos and vegetation classes still work; averaged positions need an external GNSS receiver (Bluetooth)."
                          : nil),
            GuidePage(image: "GuideTransfer", icon: "arrow.left.arrow.right", tint: Color(hexString: "#A626FF"), title: "iPad ⇄ Mac",
                      subtitle: "Two files move work between devices.",
                      points: [
                        ("doc.zipper", "Once: Save project file (.occa) and open it on the other device — the whole project with the drawing."),
                        ("square.and.arrow.up.on.square", "After each survey day: Field › Data › Export field data (.occafield) — tracks, notes, photos, markups."),
                        ("square.and.arrow.down.on.square", "On the other device: Import field data. New data is added, nothing is duplicated, the drawing stays as it is."),
                        ("hand.point.up.left", "Draw in one place (usually the Mac). Use .occa again to move the drawing itself."),
                      ]),
            GuidePage(image: "GuideCourse", icon: "printer", tint: Color(hexString: "#735810"), title: "Process and share",
                      subtitle: "From field notes to a printed course.",
                      points: [
                        ("wand.and.stars", "Open a field note and make a map object from it; turn tracks into path lines; check the survey coverage."),
                        ("flag.2.crossed", "Course Planner: controls, courses, IOF course symbols and control descriptions."),
                        ("square.and.arrow.up", "Export PDF, PNG / TIFF, OCAD-ready .omap / DXF, GPX and a field report."),
                        ("book", "This guide is always under Guide on the project list\(mac ? " and Help › OCCA Guide" : "")."),
                      ]),
        ]
    }
}

private struct GuidePageView: View {
    let page: GuidePage

    var body: some View {
        GeometryReader { geo in
        ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.l) {
                // Screenshot of that part of OCCA.
                Image(page.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: min(360, geo.size.height * 0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CP.line))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Screenshot: \(page.title)")
                    .accessibilityIdentifier("guideImage")
                HStack(spacing: CP.Space.m) {
                    Image(systemName: page.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(page.tint)
                        .frame(width: 40, height: 40)
                        .background(page.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .accessibilityHidden(true)
                    Text(page.title).font(.system(size: CP.fs(26), weight: .bold)).foregroundStyle(CP.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: CP.Space.s) {
                    Text(page.subtitle).font(.system(size: CP.fs(16))).foregroundStyle(CP.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: CP.Space.m) {
                    ForEach(page.points.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: CP.Space.m) {
                            Image(systemName: page.points[i].icon)
                                .font(.system(size: CP.fs(16), weight: .medium))
                                .foregroundStyle(page.tint)
                                .frame(width: 26)
                                .accessibilityHidden(true)
                            Text(page.points[i].text).font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let note = page.deviceNote {
                    Label(note, systemImage: "info.circle")
                        .font(.system(size: CP.fs(13)))
                        .foregroundStyle(CP.ink)
                        .padding(CP.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CP.butter.fill, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                        .accessibilityIdentifier("guideDeviceNote")
                }
            }
            .padding(.horizontal, CP.Space.xl)
            .padding(.vertical, CP.Space.l)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            // Centred vertically on tall screens, scrolls on small ones.
            .frame(minHeight: geo.size.height)
        }
        }
    }
}
