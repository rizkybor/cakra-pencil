import SwiftUI

/// Rename dialog in OCCA's style (replaces the system alert with a text field): a solid card with title, the current
/// name, a white text field, and Cancel / Save side by side, over a dimmed screen. Return saves, Esc cancels.
/// Same on iPad and Mac.
struct RenameDialog: View {
    let title: String
    var subtitle: String?
    var placeholder: String
    var confirm = "Save"
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool
    @State private var appeared = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: CP.Space.m) {
                HStack(spacing: CP.Space.s) {
                    Image(systemName: "pencil")
                        .font(.system(size: CP.fs(14), weight: .semibold))
                        .foregroundStyle(CP.sage.strong)
                        .frame(width: 30, height: 30)
                        .background(CP.sage.fill, in: RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: CP.fs(16), weight: .semibold))
                            .foregroundStyle(CP.ink)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: CP.fs(12)))
                                .foregroundStyle(CP.inkMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                TextField(placeholder, text: $text)
                    .font(.system(size: CP.fs(15)))
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if !trimmed.isEmpty { onSave() } }
                    .padding(.horizontal, CP.Space.m)
                    .frame(height: CP.isMac ? 34 : 42)
                    .searchFieldSurface(focused: focused)
                    .accessibilityIdentifier("renameField")
                HStack(spacing: CP.Space.s) {
                    Spacer(minLength: 0)
                    Button("Cancel", action: onCancel)
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("renameCancel")
                    Button(confirm, action: onSave)
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                        .disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("renameSave")
                }
            }
            .padding(CP.Space.l)
            .frame(width: 380)
            .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel + 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel + 4, style: .continuous).strokeBorder(CP.line))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("renameDialog")
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.16)) { appeared = true }
            focused = true
        }
    }
}

private struct RenameDialogModifier: ViewModifier {
    let title: String
    let subtitle: String?
    let placeholder: String
    let confirm: String
    let isPresented: Bool
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, on in
                // No sheet slide: the dialog fades in by itself.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { shown = on }
            }
            .fullScreenCover(isPresented: Binding(get: { shown }, set: { if !$0 { onCancel() } })) {
                RenameDialog(title: title, subtitle: subtitle, placeholder: placeholder, confirm: confirm,
                             text: $text, onSave: onSave, onCancel: onCancel)
                    .presentationBackground(.clear)
            }
    }
}

extension View {
    /// Shows `RenameDialog` while `isPresented`; `onSave` / `onCancel` must end it (set the caller's state).
    func renameDialog(_ title: String, subtitle: String? = nil, placeholder: String, confirm: String = "Save",
                      isPresented: Bool, text: Binding<String>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        modifier(RenameDialogModifier(title: title, subtitle: subtitle, placeholder: placeholder, confirm: confirm,
                                      isPresented: isPresented, text: text, onSave: onSave, onCancel: onCancel))
    }
}
