import SwiftUI

@main
struct CakraPencilApp: App {
    @StateObject private var repository = ProjectRepository()
    @StateObject private var symbols = SymbolLibrary()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environmentObject(repository)
                .environmentObject(symbols)
                .tint(CP.sage.strong)
        }
    }
}
