import SwiftUI

/// The X button that closes a sheet (top left). The accessibility label keeps the old word (Close, Cancel, Done) so
/// VoiceOver and UI tests read the same action; on Mac it is also the tooltip.
struct CloseIconButton: View {
    var label = "Close"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: CP.fs(14), weight: .semibold))
        }
        .accessibilityLabel(label)
        .help(label)
        #if targetEnvironment(macCatalyst)
        // The Mac toolbar draws its own capsule; OCCA's button fill inside it would show as a second box.
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        #endif
    }
}
