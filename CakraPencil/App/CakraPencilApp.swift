import CakraCore
import SwiftUI

extension Notification.Name {
    /// Help › Guide: the project list opens the guide.
    static let openGuide = Notification.Name("occa.openGuide")
}

@main
struct CakraPencilApp: App {
    @StateObject private var repository = ProjectRepository()
    @StateObject private var symbols = SymbolLibrary()
    /// Light / Dark / System (default).
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue

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
        .onAppear { (AppearanceMode(rawValue: appearance) ?? .system).apply() }
        .onChange(of: appearance) { _, v in (AppearanceMode(rawValue: v) ?? .system).apply() }
        #if DEBUG
        .onAppear { DebugSnapshot.scheduleIfRequested() }
        .onAppear { DebugGuideAudit.runIfRequested() }
        #endif
    }
}
