import SwiftUI

@main
struct CakraPencilApp: App {
    @StateObject private var repository = ProjectRepository()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environmentObject(repository)
                .tint(CP.sage.strong)
        }
    }
}
