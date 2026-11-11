import SwiftUI

/// Tab strip of a side panel (a pill on the selected tab). The labels shrink from 14 to 12 pt when the panel is too
/// narrow (iPad), so the whole strip always fits.
struct TabStrip<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    /// Accessibility identifier prefix for the tab buttons (UI tests), e.g. "courseTab-" → "courseTab-Report".
    var idPrefix: String? = nil
    let title: (Tab) -> String
    @Namespace private var pill

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip(font: 14, padding: 6)
            strip(font: 12, padding: 3)
        }
    }

    private func strip(font: CGFloat, padding: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { t in
                let on = selection == t
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = t }
                } label: {
                    Text(title(t))
                        .font(.system(size: CP.fs(font), weight: on ? .semibold : .regular))
                        .foregroundStyle(CP.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, padding)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(uiColor: .systemBackground))
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(t))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier(idPrefix.map { $0 + title(t) } ?? "")
            }
        }
        .padding(2)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
