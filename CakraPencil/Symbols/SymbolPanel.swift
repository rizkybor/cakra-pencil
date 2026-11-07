import CakraCore
import SwiftUI
import UniformTypeIdentifiers

/// Symbol panel in the inspector.
/// - Use: enabled symbols from enabled sets; tap to draw with that symbol (pen tool, rectangle, ellipse).
/// - Manage: all symbols with an enable/disable switch, plus bulk enable/disable for the filtered results.
struct SymbolPanel: View {
    @ObservedObject var model: WorkspaceModel
    @EnvironmentObject private var library: SymbolLibrary

    enum Mode: String, CaseIterable {
        case use = "Use"
        case manage = "Manage"
    }

    @State private var mode = Mode.use
    @State private var setID: UUID?
    @State private var category: SymbolCategory?
    @State private var query = ""
    @State private var importing = false
    /// List view or 6-column grid; remembered across sessions.
    @AppStorage("symbolPanelLayout") private var layout = Layout.list

    enum Layout: String, CaseIterable {
        case list, grid

        var symbol: String { self == .list ? "list.bullet" : "square.grid.3x3" }
        var label: String { self == .list ? "List" : "Grid" }
    }

    static let gridColumns = 6

    private static let ocdType = UTType(filenameExtension: "ocd", conformingTo: .data) ?? .data

    /// The set being viewed: the user's choice, or an enabled set whose scale matches the project.
    private var currentSet: SymbolSet? {
        let candidates = mode == .use ? library.enabledSets : library.sets
        if let setID, let s = candidates.first(where: { $0.id == setID }) { return s }
        return candidates.first { $0.scale == model.project.sheet.scaleDenominator }
            ?? candidates.first(where: library.isBuiltIn)
            ?? candidates.first
    }

    private var visibleSymbols: [MapSymbol] {
        guard let set = currentSet else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return set.symbols.filter { s in
            (mode == .manage || (s.isEnabled && s.isDrawable))
                && (category == nil || s.category == category)
                && (q.isEmpty || s.name.lowercased().contains(q) || s.code.hasPrefix(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            if library.sets.isEmpty {
                emptyState
            } else {
                header
                if let s = model.activeSymbol { activeRow(s) }
                if let set = currentSet, set.needsRefresh, !library.isBuiltIn(set) {
                    Text("This set was imported with an older version. Re-import \(set.sourceFile) for point symbol shapes and IOF line widths (including double lines).")
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.butter.strong)
                        .padding(CP.Space.s)
                        .background(CP.butter.fill, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                }
                HStack(spacing: CP.Space.s) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("View", selection: $layout) {
                        ForEach(Layout.allCases, id: \.self) { Image(systemName: $0.symbol).accessibilityLabel($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 84)
                }
                filters
                if mode == .manage { bulkRow }
                if layout == .grid { grid } else { list }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [Self.ocdType], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { Task { await library.importOcad(urls) } }
        }
        .alert("Import symbol set", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
    }

    // MARK: Sections

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            Text("No symbol sets yet")
                .font(.system(size: CP.fs(15), weight: .semibold))
                .foregroundStyle(CP.ink)
            Text("Import symbol sets from OCAD files (.ocd), e.g. ISOM 2017-2 or ISSprOM 2019-2. Several files at once is fine; sets are saved for all projects.")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button { importing = true } label: { Label("Import symbol set (.ocd)", systemImage: "square.and.arrow.down") }
                .buttonStyle(PrimaryButtonStyle())
            if library.isImporting { ProgressView() }
        }
    }

    private var header: some View {
        HStack(spacing: CP.Space.s) {
            Menu {
                Section("View set") {
                    ForEach(mode == .use ? library.enabledSets : library.sets) { s in
                        Button {
                            setID = s.id
                        } label: {
                            if s.id == currentSet?.id { Label(s.name, systemImage: "checkmark") } else { Text(s.name) }
                        }
                    }
                }
                Section("Enabled sets (shown in Use)") {
                    ForEach(library.sets) { s in
                        Toggle(isOn: Binding(get: { s.isEnabled }, set: { library.setEnabled(s.id, $0) })) {
                            Text(verbatim: "\(s.name) · 1:\(s.scale)")
                        }
                    }
                }
                Section {
                    Button { importing = true } label: { Label("Import symbol set (.ocd)…", systemImage: "square.and.arrow.down") }
                    if let s = currentSet, !library.isBuiltIn(s) {
                        Button(role: .destructive) {
                            library.delete(s.id)
                            setID = nil
                        } label: { Label("Delete set \(s.name)", systemImage: "trash") }
                    }
                }
            } label: {
                HStack(spacing: CP.Space.xs) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(currentSet?.name ?? "No enabled set")
                            .font(.system(size: CP.fs(13), weight: .semibold))
                            .foregroundStyle(CP.ink)
                            .lineLimit(1)
                        if let s = currentSet {
                            Text(verbatim: "1:\(s.scale) · \(s.enabledCount)/\(s.symbols.count) enabled")
                                .font(CP.mono(11))
                                .foregroundStyle(CP.inkMuted)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
                }
                .padding(.horizontal, CP.Space.s)
                .padding(.vertical, CP.Space.xs)
                .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            }
            if library.isImporting { ProgressView().controlSize(.small) }
        }
    }

    private func activeRow(_ s: MapSymbol) -> some View {
        HStack(spacing: CP.Space.s) {
            SymbolSwatch(symbol: s)
            VStack(alignment: .leading, spacing: 1) {
                Text("Active symbol").font(.system(size: CP.fs(11))).foregroundStyle(CP.sage.strong)
                Text("\(s.code) \(s.name)").font(.system(size: CP.fs(13), weight: .medium)).foregroundStyle(CP.ink).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Clear") { model.clearSymbol() }
                .font(.system(size: CP.fs(13)))
        }
        .padding(CP.Space.s)
        .background(CP.sage.fill, in: RoundedRectangle(cornerRadius: CP.Radius.control))
    }

    private var filters: some View {
        VStack(spacing: CP.Space.xs) {
            HStack(spacing: CP.Space.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(CP.inkMuted).font(.system(size: CP.fs(13)))
                TextField("Search code or name", text: $query)
                    .font(.system(size: CP.fs(13)))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, CP.Space.s)
            .frame(height: 32)
            .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CP.Space.xs) {
                    chip("All", isOn: category == nil) { category = nil }
                    ForEach(SymbolCategory.allCases.filter { $0 != .other }) { c in
                        chip(c.label, isOn: category == c) { category = c }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: CP.fs(12), weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? CP.sage.strong : CP.ink)
                .padding(.horizontal, CP.Space.s)
                .frame(height: 26)
                .background(isOn ? CP.sage.fill : CP.paper2, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var bulkRow: some View {
        HStack {
            Text("\(visibleSymbols.count) symbols").font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            Spacer()
            Button("Enable all") { bulk(true) }
            Button("Disable all") { bulk(false) }
        }
        .font(.system(size: CP.fs(12), weight: .medium))
        .disabled(visibleSymbols.isEmpty)
    }

    private func bulk(_ on: Bool) {
        guard let s = currentSet else { return }
        library.setSymbols(Set(visibleSymbols.map(\.number)), enabled: on, in: s.id)
    }

    private var list: some View {
        List {
            if visibleSymbols.isEmpty {
                Text(mode == .use ? "No enabled symbols here. Open Manage mode to enable some." : "No matching symbols.")
                    .font(.system(size: CP.fs(13)))
                    .foregroundStyle(CP.inkMuted)
                    .listRowBackground(Color.clear)
            }
            ForEach(visibleSymbols) { s in
                row(s)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: 6-column grid

    /// Fixed 6 columns; rows grow with the number of filtered symbols.
    private var grid: some View {
        ScrollView {
            if visibleSymbols.isEmpty {
                Text(mode == .use ? "No enabled symbols here. Open Manage mode to enable some." : "No matching symbols.")
                    .font(.system(size: CP.fs(13)))
                    .foregroundStyle(CP.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: CP.Space.xs), count: Self.gridColumns),
                      spacing: CP.Space.xs) {
                ForEach(visibleSymbols) { s in cell(s) }
            }
            .padding(.vertical, CP.Space.xs)
        }
    }

    private func cell(_ s: MapSymbol) -> some View {
        let active = isActive(s)
        return VStack(spacing: 2) {
            SymbolSwatch(symbol: s, size: CGSize(width: 34, height: 28))
                .overlay(alignment: .topTrailing) {
                    if mode == .manage && !s.isEnabled {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: CP.fs(11)))
                            .foregroundStyle(CP.rose.strong, CP.paper)
                            .offset(x: 4, y: -4)
                    }
                }
            Text(verbatim: s.code)
                .font(CP.mono(9, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? CP.sage.strong : CP.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(active ? CP.sage.fill : Color.clear, in: RoundedRectangle(cornerRadius: CP.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(active ? CP.sage.strong : Color.clear, lineWidth: 1.5))
        .opacity(dimmed(s) ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture { tap(s) }
        .contextMenu {
            Text("\(s.code) \(s.name) · \(s.kind.label)")
            if mode == .use, s.isDrawable { Button { model.useSymbol(s) } label: { Label("Use symbol", systemImage: "pencil.tip") } }
            if let set = currentSet {
                Button { library.setSymbols([s.number], enabled: !s.isEnabled, in: set.id) } label: {
                    Label(s.isEnabled ? "Disable" : "Enable", systemImage: s.isEnabled ? "eye.slash" : "eye")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.code) \(s.name), \(s.kind.label)\(s.isEnabled ? "" : ", disabled")")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Behavior shared by list & grid

    private func isActive(_ s: MapSymbol) -> Bool {
        model.activeSymbol?.number == s.number && model.activeSymbol?.name == s.name
    }

    private func dimmed(_ s: MapSymbol) -> Bool {
        mode == .manage ? !s.isEnabled : !s.isDrawable
    }

    /// Use: pick a symbol to draw with. Manage (grid): enabled ↔ disabled.
    private func tap(_ s: MapSymbol) {
        switch mode {
        case .use:
            if model.tool.selects, model.selectedFeature != nil {
                // An object is selected: the symbol becomes the "Switch symbol" candidate (tool unchanged), like OOM.
                model.chooseSymbolForSelection(s)
            } else if s.isDrawable {
                model.useSymbol(s)
            } else {
                model.notice = "\(s.kind.label) symbols can't be drawn yet. Use a point, line, or area symbol."
            }
        case .manage:
            guard layout == .grid, let set = currentSet else { return }
            library.setSymbols([s.number], enabled: !s.isEnabled, in: set.id)
        }
    }

    private func row(_ s: MapSymbol) -> some View {
        let active = isActive(s)
        return HStack(spacing: CP.Space.s) {
            SymbolSwatch(symbol: s)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: CP.Space.xs) {
                    Text(s.code).font(CP.mono(12, weight: .medium)).foregroundStyle(CP.ink)
                    Text(s.kind.label).font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
                }
                Text(s.name)
                    .font(.system(size: CP.fs(13)))
                    .foregroundStyle(s.isEnabled ? CP.ink : CP.inkMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if mode == .manage, let set = currentSet {
                Toggle("Enabled", isOn: Binding(get: { s.isEnabled }, set: { library.setSymbols([s.number], enabled: $0, in: set.id) }))
                    .labelsHidden()
                    .tint(CP.sage.strong)
            } else if !s.isDrawable {
                Text("not supported yet").font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { tap(s) }
        .listRowBackground(active ? CP.sage.fill : Color.clear)
        .opacity(mode == .use && !s.isDrawable ? 0.5 : 1)
    }
}

/// Small symbol sample: thick line, filled box, point, or "T".
struct SymbolSwatch: View {
    let symbol: MapSymbol
    /// Sample box size; contents are scaled from a base size of 26 × 22 pt.
    var size = CGSize(width: 26, height: 22)

    var body: some View {
        let color = Color(hexString: symbol.colorHex)
        let k = min(size.width / 26, size.height / 22)
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(CP.paper).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(CP.line))
            switch symbol.kind {
            case .line:
                Capsule().fill(color).frame(width: 18 * k, height: max(1.5, min(symbol.drawingWidthMM * 8, 6)) * k)
            case .area:
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 18 * k, height: 14 * k)
            case .point:
                if let elements = symbol.pointElements, !elements.isEmpty {
                    // Original shape, scaled to fit the 18 pt sample.
                    Canvas { ctx, size in
                        let k = (min(size.width, size.height) - 2) / max(elements.diameterMM, 0.1)
                        let c = CGPoint(x: size.width / 2, y: size.height / 2)
                        ctx.withCGContext { cg in
                            PointSymbolRenderer.draw(elements, in: cg, mmToUnits: k) { CGPoint(x: c.x + $0.x * k, y: c.y - $0.y * k) }
                        }
                    }
                    .frame(width: 18 * k, height: 18 * k)
                } else {
                    Circle().fill(color).frame(width: 7 * k, height: 7 * k)
                }
            case .text:
                Text("T").font(.system(size: CP.fs(12) * k, weight: .bold)).foregroundStyle(color)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}
