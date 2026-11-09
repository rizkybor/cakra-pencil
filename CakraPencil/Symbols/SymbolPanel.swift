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

    private static let setTypes: [UTType] = [.occaSymbolSet] + ["ocd", "omap", "xmap"].map { UTType(filenameExtension: $0, conformingTo: .data) ?? .data }

    private var mapScale: Int { model.project.sheet.scaleDenominator }

    /// The set being viewed: the user's choice, or the best enabled set for the map (same scale, then the same IOF
    /// standard; map sets before course design sets). Sized for the map: a set of the same standard at another scale is
    /// enlarged/reduced (e.g. the ISOM 1:10000 set × 0.667 on a 1:15000 map).
    private var currentSet: SymbolSet? {
        let candidates = mode == .use ? library.enabledSets : library.sets
        let preferred = library.preferredSets(forMapScale: mapScale)
        let base = setID.flatMap { id in candidates.first { $0.id == id } }
            ?? preferred.lazy.compactMap { p in candidates.first { $0.id == p.id } }.first
            ?? candidates.first
        guard let base else { return nil }
        return preferred.first { $0.id == base.id } ?? base.scaled(by: base.sizeFactor(forMapScale: mapScale))
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
                    Text("This set was imported with an older version. Re-import \(set.sourceFile) for point symbol shapes, IOF line widths (including double lines) and area patterns (marsh, scattered trees…).")
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.butter.strong)
                        .padding(CP.Space.s)
                        .background(CP.butter.fill, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                }
                HStack(spacing: CP.Space.s) {
                    Segmented("Mode", selection: $mode, Mode.allCases.map { .init($0, $0.rawValue) })
                    Segmented("View", selection: $layout, Layout.allCases.map { .init($0, $0.label, icon: $0.symbol, iconOnly: true) })
                    .frame(width: 84)
                }
                filters
                if mode == .manage { bulkRow }
                if layout == .grid { grid } else { list }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.setTypes, allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { Task { await library.importOcad(urls) } }
        }
        .alert("Import symbol set", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
    }

    /// Export a set (at its own scale, with its enabled/disabled choices) as an `.occasym` file.
    /// (A system document picker, not `fileExporter`: the workspace already has a file exporter, and SwiftUI ignores a
    /// second one nested inside it.)
    private func export(_ set: SymbolSet) {
        do {
            let name = projectFileName(set.name.replacingOccurrences(of: " · ", with: " "))
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SymbolSetExport", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name).appendingPathExtension(OccaSymbolFile.fileExtension)
            try library.exportFile(set).write(to: url, options: .atomic)
            DocumentExport.present(url)
        } catch {
            library.lastError = "Couldn't export symbol set: \(error.localizedDescription)"
        }
    }

    // MARK: Sections

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            Text("No symbol sets yet")
                .font(.system(size: CP.fs(15), weight: .semibold))
                .foregroundStyle(CP.ink)
            Text("Import symbol sets from OCCA (.occasym), OCAD (.ocd), or OpenOrienteering Mapper (.omap, .xmap) files, e.g. ISOM 2017-2 or ISSprOM 2019-2. Several files at once is fine; sets are saved for all projects.")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button { if LicenseManager.shared.require(.customSymbols) { importing = true } } label: { Label("Import symbol set (.occasym, .ocd, .omap)", systemImage: "square.and.arrow.down") }
                .buttonStyle(PrimaryButtonStyle())
            if library.isImporting { ProgressView() }
        }
    }

    /// Symbol set menu: view a set, enable/disable sets, import/export/delete.
    private var setMenuItems: [MenuItem] {
        var items: [MenuItem] = (mode == .use ? library.enabledSets : library.sets).map { s in
            .action(s.name, checked: s.id == currentSet?.id, section: "View set") { setID = s.id }
        }
        items += library.sets.map { s in
            .toggle("\(s.name) · 1:\(s.scale)", isOn: Binding(get: { s.isEnabled }, set: { library.setEnabled(s.id, $0) }),
                    section: "Enabled sets (shown in Use)")
        }
        items.append(.divider)
        items.append(.action("Import symbol set (.occasym, .ocd, .omap)…", icon: "square.and.arrow.down") { if LicenseManager.shared.require(.customSymbols) { importing = true } })
        if let s = currentSet, let base = library.sets.first(where: { $0.id == s.id }) {
            items.append(.action("Export \(s.name) (.occasym)…", icon: "square.and.arrow.up", identifier: "exportSymbolSet") { export(base) })
        }
        if let s = currentSet, !library.isBuiltIn(s) {
            items.append(.action("Delete set \(s.name)", icon: "trash", role: .destructive) {
                library.delete(s.id)
                setID = nil
            })
        }
        return items
    }

    private var header: some View {
        HStack(spacing: CP.Space.s) {
            SolidMenu(items: setMenuItems, width: 320) {
                HStack(spacing: CP.Space.xs) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentSet?.name ?? "No enabled set")
                            .font(.system(size: CP.fs(13), weight: .semibold))
                            .foregroundStyle(CP.ink)
                            .lineLimit(1)
                        if let s = currentSet {
                            let k = s.sizeFactor(forMapScale: mapScale)
                            Text(verbatim: "1:\(s.scale)\(abs(k - 1) > 0.001 ? " · sized \(Int((k * 100).rounded()))% for 1:\(mapScale)" : "") · \(s.enabledCount)/\(s.symbols.count) enabled")
                                .font(CP.mono(11))
                                .foregroundStyle(CP.inkMuted)
                                .lineSpacing(3)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: CP.Space.s)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
                }
                .padding(.horizontal, CP.Space.m)
                .padding(.vertical, CP.Space.s)
                .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                .contentShape(Rectangle())
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
            .searchFieldSurface()

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
                .background(isOn ? CP.sage.fill : CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous))
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
            Button { model.symbolGuideSearching = false; model.openSymbolGuide(s.code, name: s.name) } label: { Label("Symbol guide", systemImage: "book") }
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
            if mode == .use {
                Button { model.symbolGuideSearching = false; model.openSymbolGuide(s.code, name: s.name) } label: {
                    Image(systemName: model.symbolGuide?.code == s.code ? "book.fill" : "book")
                        .font(.system(size: CP.fs(14)))
                        .foregroundStyle(model.symbolGuide?.code == s.code ? CP.sage.strong : CP.inkMuted)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Symbol guide \(s.code)")
                .help("Symbol guide: \(s.code) \(s.name)")
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
            // Always on light "map paper" (also in dark mode): map symbols are printed on white, and black ones
            // (walls, fences, boulders) would vanish on a dark tile.
            RoundedRectangle(cornerRadius: 3).fill(CP.mapPaper)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.14)))
            switch symbol.kind {
            case .line:
                if let deco = symbol.decoration {
                    // Line with its ISOM decoration (tags, wall dots…), enlarged to be readable.
                    Canvas { ctx, sz in
                        let u = 7.0, y = sz.height / 2 - 1
                        let pts = [Point2D(x: 1, y: y), Point2D(x: sz.width - 1, y: y)]
                        ctx.withCGContext { cg in
                            cg.setStrokeColor(UIColor(hexString: symbol.colorHex).cgColor)
                            cg.setLineWidth(max(1.5, min(symbol.drawingWidthMM * 8, 4)))
                            cg.move(to: CGPoint(x: pts[0].x, y: y)); cg.addLine(to: CGPoint(x: pts[1].x, y: y)); cg.strokePath()
                            var d = deco
                            d.spacingMM = deco.spacingMM > 0 ? max(deco.spacingMM, 0.9) : 0
                            OrnamentRenderer.draw(SymbolOrnaments.decorationMarks(d, along: pts, unitsPerMM: u, lineWidthMM: 0.3,
                                                                                  colorHex: symbol.colorHex, yUp: false),
                                                  in: cg, unitsPerMM: u, minWidth: 1)
                        }
                    }
                    .frame(width: 18 * k, height: 14 * k)
                } else {
                    Capsule().fill(color).frame(width: 18 * k, height: max(1.5, min(symbol.drawingWidthMM * 8, 6)) * k)
                }
            case .area:
                if let patterns = symbol.patterns, !patterns.isEmpty {
                    // Fill (unless pattern-only) and the ISOM pattern, enlarged ×3 so it reads at swatch size.
                    Canvas { ctx, sz in
                        let rect = CGRect(origin: .zero, size: sz)
                        let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
                        ctx.withCGContext { cg in
                            if !SymbolOrnaments.isPatternOnly(fillHex: symbol.colorHex, patterns: patterns) {
                                cg.addPath(path); cg.setFillColor(UIColor(hexString: symbol.colorHex).cgColor); cg.fillPath()
                            }
                            OrnamentRenderer.drawPatterns(patterns, outline: path, rect: Rect2D(minX: 0, minY: 0, maxX: sz.width, maxY: sz.height),
                                                          in: cg, unitsPerMM: 9, yUp: false, minWidth: 0.6)
                        }
                    }
                    .frame(width: 18 * k, height: 14 * k)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(color)
                        // Thin edge so white/very light areas (405 forest, 401 open land…) still show on the paper.
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                        .frame(width: 18 * k, height: 14 * k)
                }
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
