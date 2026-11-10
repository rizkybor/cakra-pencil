import CakraCore
import SwiftUI

extension Notification.Name {
    /// Help › Guide: the project list opens the guide.
    static let openGuide = Notification.Name("occa.openGuide")
}

@main
struct CakraPencilApp: App {
    /// Tracks Shift / ⌘ from key presses (multi-select with Shift + click on Mac).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var repository = ProjectRepository()
    @StateObject private var symbols = SymbolLibrary()
    /// Light / Dark / System (default).
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Export files left over from the last session (shared already) — see TempExports.
        DispatchQueue.global(qos: .utility).async { TempExports.cleanUp() }
        // iPad segmented controls: segment widths follow their labels, so longer labels ("Descriptions") stay readable.
        UISegmentedControl.appearance().apportionsSegmentWidthsByContent = true
        #if DEBUG
        DebugFixtures.restoreIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-cp-splash-preview") {
                SplashView()
                    .onAppear { MacWindow.configure() }
                    .onAppear { DebugSnapshot.scheduleIfRequested() }
            } else {
                mainView
            }
            #else
            mainView
            #endif
        }
        .commands {
            // Mac menu bar (and iPad keyboard menu): View › Appearance.
            CommandGroup(after: .toolbar) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            // Mac menu bar: Help › OCCA Guide (iPad keyboards show it under Help too).
            CommandGroup(replacing: .help) {
                Button("\(AppInfo.name) Guide") { NotificationCenter.default.post(name: .openGuide, object: nil) }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }
    }

    /// The project list, with the splash screen on top every time the app opens.
    private var mainView: some View {
        SplashContainer {
            ProjectListView()
                .environmentObject(repository)
                .environmentObject(symbols)
                .tint(CP.sage.strong)
        }
        .onAppear { MacWindow.configure() }
        // "STARTER" / "TRIAL" in the corner of every screen; nothing on paid plans.
        .onAppear { PlanWatermark.install() }
        .onAppear { (AppearanceMode(rawValue: appearance) ?? .system).apply() }
        .onChange(of: appearance) { _, v in (AppearanceMode(rawValue: v) ?? .system).apply() }
        // License key: refresh the signed token when it's due (about weekly), at launch and on return to the app.
        .onChange(of: scenePhase, initial: true) { _, phase in if phase == .active { LicenseManager.shared.start() } }
        #if DEBUG
        .onAppear { DebugSnapshot.scheduleIfRequested() }
        .onAppear { DebugGuideAudit.runIfRequested() }
        #endif
    }
}
