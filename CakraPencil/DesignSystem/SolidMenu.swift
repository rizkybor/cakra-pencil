import SwiftUI

/// One row of a `SolidMenu`.
struct MenuItem: Identifiable {
    enum Kind {
        case action(() -> Void)
        case toggle(Binding<Bool>)
        case divider
    }

    let id = UUID()
    var title: String
    var icon: String?
    /// Custom icon (e.g. an IOF description pictogram); wins over `icon`.
    var image: Image?
    var role: ButtonRole?
    var checked = false
    var disabled = false
    /// Section header shown above the first row of a run of rows with the same section.
    var section: String?
    /// Accessibility identifier of the row (UI tests).
    var identifier: String?
    var kind: Kind

    static func action(_ title: String, icon: String? = nil, image: Image? = nil, role: ButtonRole? = nil, checked: Bool = false,
                       disabled: Bool = false, section: String? = nil, identifier: String? = nil,
                       _ run: @escaping () -> Void) -> MenuItem {
        MenuItem(title: title, icon: icon, image: image, role: role, checked: checked, disabled: disabled, section: section,
                 identifier: identifier, kind: .action(run))
    }

    static func toggle(_ title: String, isOn: Binding<Bool>, section: String? = nil) -> MenuItem {
        MenuItem(title: title, section: section, kind: .toggle(isOn))
    }

    static var divider: MenuItem { MenuItem(title: "", kind: .divider) }
}

/// Dropdown menu with a solid panel (no translucent system menu / glass): a button that opens a popover listing
/// `items`. Picking an action closes the popover first and then runs it, so actions that present a sheet or file
/// picker work. Toggles stay open. Same on iPad and Mac.
struct SolidMenu<Label: View>: View {
    let items: [MenuItem]
    var width: CGFloat = 280
    /// false: the label keeps the surrounding button style (e.g. inside a `ButtonGroup`).
    var plain = true
    @ViewBuilder var label: () -> Label

    @State private var showing = false
    @State private var pending: (() -> Void)?

    var body: some View {
        Button { showing = true } label: { label() }
            .modifier(PlainButton(on: plain))
            .popover(isPresented: $showing) {
                SolidMenuList(items: items, width: width) { action in
                    pending = action
                    showing = false
                }
                .presentationBackground(CP.paper)
                .presentationCompactAdaptation(.popover)
            }
            .onChange(of: showing) { _, open in
                guard !open, let run = pending else { return }
                pending = nil
                // After the popover is gone, so the action may present something itself.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { run() }
            }
    }
}

private struct PlainButton: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.buttonStyle(.plain) } else { content }
    }
}

private struct SolidMenuList: View {
    let items: [MenuItem]
    let width: CGFloat
    let pick: (@escaping () -> Void) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if let section = item.section, i == 0 || items[i - 1].section != section {
                        Text(section)
                            .font(.system(size: CP.fs(11), weight: .semibold))
                            .foregroundStyle(CP.inkMuted)
                            .padding(.horizontal, CP.Space.m)
                            .padding(.top, i == 0 ? CP.Space.xs : CP.Space.s)
                            .padding(.bottom, 2)
                    }
                    row(item)
                }
            }
            .padding(.vertical, CP.Space.xs)
        }
        .frame(width: width)
        .frame(maxHeight: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(CP.paper)
    }

    @ViewBuilder
    private func row(_ item: MenuItem) -> some View {
        switch item.kind {
        case .divider:
            Rectangle().fill(CP.line).frame(height: 1).padding(.vertical, 4)
        case let .toggle(isOn):
            Toggle(isOn: isOn) { Text(item.title).font(.system(size: CP.fs(14))).foregroundStyle(CP.ink) }
                .tint(CP.sage.strong)
                .padding(.horizontal, CP.Space.m)
                .frame(minHeight: CP.isMac ? 30 : 40)
        case let .action(run):
            Button(role: item.role) { pick(run) } label: {
                HStack(spacing: CP.Space.s) {
                    Group {
                        if item.checked {
                            Image(systemName: "checkmark").font(.system(size: CP.fs(12), weight: .bold))
                        } else if let image = item.image {
                            image.resizable().scaledToFit()
                        } else if let icon = item.icon {
                            Image(systemName: icon)
                        }
                    }
                    .frame(width: 20, height: 18)
                    Text(item.title).lineLimit(2)
                    Spacer(minLength: 0)
                }
                .font(.system(size: CP.fs(14), weight: item.checked ? .semibold : .regular))
                .foregroundStyle(item.role == .destructive ? CP.rose.strong : CP.ink)
                .padding(.horizontal, CP.Space.m)
                .frame(minHeight: CP.isMac ? 30 : 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(SolidMenuRowStyle())
            .disabled(item.disabled)
            .accessibilityLabel(item.title)
            .accessibilityIdentifier(item.identifier ?? "menuItem")
            .accessibilityAddTraits(item.checked ? .isSelected : [])
        }
    }
}

private struct SolidMenuRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? CP.sand.fill : Color.clear)
            .opacity(isEnabled ? 1 : 0.4)
    }
}
