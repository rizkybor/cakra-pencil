import SwiftUI

/// Segmented choice. iPad: the system segmented picker. Mac: the same control drawn with a modest corner radius
/// (the Mac system control is a full capsule, which doesn't fit OCCA's panels).
struct Segmented<Value: Hashable>: View {
    struct Item {
        var value: Value
        var title: String
        var icon: String? = nil
        /// Show only the icon (the title is the accessibility label).
        var iconOnly = false
        var bold = false

        init(_ value: Value, _ title: String, icon: String? = nil, iconOnly: Bool = false, bold: Bool = false) {
            self.value = value
            self.title = title
            self.icon = icon
            self.iconOnly = iconOnly
            self.bold = bold
        }
    }

    let title: String
    @Binding var selection: Value
    let items: [Item]

    init(_ title: String, selection: Binding<Value>, _ items: [Item]) {
        self.title = title
        self._selection = selection
        self.items = items
    }

    var body: some View {
        if CP.isMac {
            MacSegmented(title: title, selection: $selection, items: items)
        } else {
            Picker(title, selection: $selection) {
                ForEach(items.indices, id: \.self) { i in
                    label(items[i]).tag(items[i].value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func label(_ item: Item) -> some View {
        if let icon = item.icon, item.iconOnly {
            Image(systemName: icon).accessibilityLabel(item.title)
        } else if let icon = item.icon {
            Label(item.title, systemImage: icon)
        } else if item.bold {
            Text(item.title).fontWeight(.bold)
        } else {
            Text(item.title)
        }
    }
}

private struct MacSegmented<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let items: [Segmented<Value>.Item]
    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var thumb

    private static var outer: CGFloat { CP.Radius.chip }
    private static var inner: CGFloat { 5 }

    var body: some View {
        SegmentRow(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let on = item.value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = item.value }
                } label: {
                    HStack(spacing: 5) {
                        if let icon = item.icon { Image(systemName: icon) }
                        if !item.iconOnly { Text(item.title).lineLimit(1).minimumScaleFactor(0.8) }
                    }
                    .font(.system(size: CP.fs(13), weight: on || item.bold ? .semibold : .regular))
                    .foregroundStyle(CP.ink)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: Self.inner, style: .continuous)
                                .fill(CP.ink.opacity(0.16))
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(CP.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: Self.outer, style: .continuous))
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Segments side by side, filling the width. Each segment gets at least its natural width (so labels stay readable);
/// spare width is shared equally. When the row is too narrow, widths shrink in proportion (labels then scale down a
/// little, see `minimumScaleFactor`).
private struct SegmentRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = ideal.map(\.height).max() ?? 0
        let natural = ideal.map(\.width).reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: proposal.width ?? natural, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let available = max(bounds.width - gaps, 0)
        let total = ideal.reduce(0, +)
        let widths: [CGFloat]
        if total <= available {
            let extra = (available - total) / CGFloat(subviews.count)
            widths = ideal.map { $0 + extra }
        } else {
            widths = ideal.map { total > 0 ? $0 * available / total : available / CGFloat(subviews.count) }
        }
        var x = bounds.minX
        for (i, sub) in subviews.enumerated() {
            sub.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: widths[i], height: bounds.height))
            x += widths[i] + spacing
        }
    }
}
