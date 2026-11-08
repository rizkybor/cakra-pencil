import SwiftUI

/// A small ⓘ button that shows a longer explanation in a popover, so panels stay clean. Tap (iPad) or click (Mac);
/// on Mac the text is also the hover tooltip.
struct InfoHint: View {
    let text: String
    @State private var showing = false

    init(_ text: String) { self.text = text }

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: CP.fs(14)))
                .foregroundStyle(CP.inkMuted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel("Info")
        .accessibilityHint(text)
        .popover(isPresented: $showing) {
            Text(text)
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300, alignment: .leading)
                .padding(CP.Space.l)
                .presentationCompactAdaptation(.popover)
        }
    }
}
