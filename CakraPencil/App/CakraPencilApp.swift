import SwiftUI

@main
struct CakraPencilApp: App {
    @StateObject private var repository = ProjectRepository()
    @StateObject private var symbols = SymbolLibrary()

    init() {
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
        #if DEBUG
        .onAppear { DebugSnapshot.scheduleIfRequested() }
        #endif
    }
}
