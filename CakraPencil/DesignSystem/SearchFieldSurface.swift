import SwiftUI

/// Search fields (symbols, places, projects, Symbol Guide): white box with black text in light and dark mode,
/// so what you type always reads clearly. Placeholder, icon, and caret use their light-mode colors.
struct SearchFieldSurface: ViewModifier {
    var focused = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.black)
            .background(Color.white, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control)
                .strokeBorder(focused ? CP.sky.strong : Color.black.opacity(0.14), lineWidth: focused ? 1.5 : 1))
            .environment(\.colorScheme, .light)
    }
}

extension View {
    func searchFieldSurface(focused: Bool = false) -> some View { modifier(SearchFieldSurface(focused: focused)) }
}
