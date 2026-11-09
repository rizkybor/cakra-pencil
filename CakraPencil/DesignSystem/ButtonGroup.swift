import SwiftUI

/// Top-bar buttons that belong together (undo/redo, panel/save, import/preview) in one outlined box with thin
/// dividers, the same height as the compact Export button (28 pt on Mac, 36 pt on iPad).
struct ButtonGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(2)
            .background(CP.sand.fill, in: RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous).strokeBorder(CP.sand.strong.opacity(0.18)))
            .fixedSize()
    }
}

/// Thin vertical line between two buttons of a `ButtonGroup`.
struct GroupDivider: View {
    var body: some View {
        Rectangle().fill(CP.sand.strong.opacity(0.2)).frame(width: 1, height: CP.isMac ? 14 : 18).padding(.horizontal, 2)
    }
}

/// Button inside a `ButtonGroup`: icon only (square) or icon + title, no own border.
struct GroupedButtonStyle: ButtonStyle {
    var isActive = false
    /// Text/icon color (e.g. the course purple); default ink.
    var tint: Color? = nil
    @Environment(\.isEnabled) private var isEnabled

    static var innerSide: CGFloat { CP.isMac ? 24 : 32 }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: CP.fs(14), weight: .medium))
            .foregroundStyle(isActive ? CP.sage.strong : (tint ?? CP.sand.strong))
            .padding(.horizontal, 6)
            .frame(minWidth: Self.innerSide, minHeight: Self.innerSide)
            .background(isActive ? CP.sage.fill : (configuration.isPressed ? CP.sand.strong.opacity(0.12) : .clear),
                        in: RoundedRectangle(cornerRadius: CP.Radius.chip - 2, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

/// Tinted top-bar button (e.g. Course in the course purple): soft fill, colored title, same height as a group.
struct TintedButtonStyle: ButtonStyle {
    var tone: CP.Tone
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: CP.fs(14), weight: .semibold))
            .foregroundStyle(tone.strong)
            .padding(.horizontal, 10)
            .frame(height: GroupedButtonStyle.innerSide + 4)
            .background(tone.fill.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous).strokeBorder(tone.strong.opacity(0.25)))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}
