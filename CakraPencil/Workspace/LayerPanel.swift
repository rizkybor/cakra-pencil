import CakraCore
import SwiftUI
import UniformTypeIdentifiers

/// Layers panel: every vector object (topmost = drawn last) plus the pencil sketch group.
/// Tap a row = select the object. Eye = show/hide (hidden objects aren't exported), padlock = lock.
struct LayerPanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var renaming: Feature?
    @State private var newName = ""
    @State private var reordering = false
    @State private var importingOcad = false

    /// OCAD (.ocd) or OpenOrienteering Mapper (.omap / .xmap) map.
    static let mapFileTypes: [UTType] = ["ocd", "omap", "xmap"].map { UTType(filenameExtension: $0, conformingTo: .data) ?? .data }

    private var layers: [Feature] { model.features.reversed() }

    /// UI tests (DEBUG, `-cp-restore-fixtures`): every row's subtitle is mirrored in one invisible list, so tests can
    /// count rows of the lazy List no matter which rows are currently rendered.
    #if DEBUG
    static let testMode = ProcessInfo.processInfo.arguments.contains("-cp-restore-fixtures")
    #else
    static let testMode = false
    #endif

    static func subtitle(_ f: Feature) -> String {
        f.kind == .point
            ? "Point · Ø \(Fmt.mm(f.widthMM)) · \(Int((f.effectiveSizeFactor * 100).rounded()))%"
            : "\(f.kind.label) · \(f.nodes.count) points · \(Fmt.mm(f.widthMM))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack {
                // English number format like the rest of the app ("2,210", not the region's "2.210").
                Text(verbatim: "\(Fmt.number(Double(model.features.count), decimals: 0)) objects · \(Fmt.number(Double(model.strokes.count), decimals: 0)) strokes")
                    .background {
                        if Self.testMode {
                            VStack(spacing: 0) { ForEach(layers) { Text(verbatim: Self.subtitle($0)).font(.system(size: 1)).accessibilityIdentifier("layerRowMirror") } }
                                .frame(width: 1, height: 1, alignment: .top)
                                .opacity(0.02)
                                .allowsHitTesting(false)
                        }
                    }
                    .font(.system(size: CP.fs(13)))
                    .foregroundStyle(CP.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                Spacer()
                Menu {
                    Button { importingOcad = true } label: { Label("OCAD / OOM map (.ocd, .omap)…", systemImage: "doc.badge.plus") }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.system(size: CP.fs(13), weight: .medium))
                }
                .menuIndicator(.hidden)
                .fixedSize()
                Button(reordering ? "Done" : "Reorder") { reordering.toggle() }
                    .font(.system(size: CP.fs(13), weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .disabled(model.features.count < 2)
            }

            List {
                Section {
                    if layers.isEmpty {
                        Text("No objects yet. Use the Pen tool, Rectangle, or Ellipse in the left rail.")
                            .font(.system(size: CP.fs(13)))
                            .foregroundStyle(CP.inkMuted)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(layers) { f in
                        row(f)
                    }
                    .onMove { model.moveFeatures(fromLayerOffsets: $0, toLayerOffset: $1) }
                } header: {
                    Text("Vector objects")
                }

                Section {
                    HStack(spacing: CP.Space.s) {
                        visibilityButton(isOn: model.sketchVisible) { model.sketchVisible.toggle() }
                        Image(systemName: "pencil.tip").foregroundStyle(CP.inkMuted).frame(width: 18)
                        Text("Pencil sketch")
                            .font(.system(size: CP.fs(15)))
                            .foregroundStyle(model.sketchVisible ? CP.ink : CP.inkMuted)
                        Spacer()
                        Text(verbatim: "\(model.strokes.count)").font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Sketch")
                }

                Section {
                    let g = model.project.grid
                    HStack(spacing: CP.Space.s) {
                        visibilityButton(isOn: g.isEnabled) { model.toggleNorthLines() }
                        Image(systemName: "line.3.horizontal").rotationEffect(.degrees(90)).foregroundStyle(CP.inkMuted).frame(width: 18)
                        Text("North lines")
                            .font(.system(size: CP.fs(15)))
                            .foregroundStyle(g.isEnabled ? CP.ink : CP.inkMuted)
                        Spacer()
                        Text(verbatim: "\(Int(g.spacingM)) m").font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Grid")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(reordering ? .active : .inactive))
        }
        .fileImporter(isPresented: $importingOcad, allowedContentTypes: Self.mapFileTypes) { result in
            if case let .success(url) = result { Task { await model.importOcad(from: url) } }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Object name", text: $newName)
            Button("Save") {
                if let f = renaming {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.updateFeature(f.id) { $0.name = name }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func row(_ f: Feature) -> some View {
        let selected = model.isSelected(f.id)
        return HStack(spacing: CP.Space.s) {
            visibilityButton(isOn: f.isVisible) { model.updateFeature(f.id) { $0.isVisible.toggle() } }
            ZStack {
                if f.kind == .area {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hexString: f.colorHex).opacity(0.35))
                }
                Image(systemName: f.kind == .area ? "square" : (f.kind == .point ? "smallcircle.filled.circle" : "scribble"))
                    .font(.system(size: CP.fs(13)))
                    .foregroundStyle(Color(hexString: f.colorHex))
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(f.displayName)
                    .font(.system(size: CP.fs(15)))
                    .foregroundStyle(f.isVisible ? CP.ink : CP.inkMuted)
                    .lineLimit(1)
                Text(Self.subtitle(f))
                    .font(CP.mono(11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(CP.inkMuted)
            }
            Spacer(minLength: 0)
            Button { model.updateFeature(f.id) { $0.isLocked.toggle() } } label: {
                Image(systemName: f.isLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(f.isLocked ? CP.peach.strong : CP.inkMuted.opacity(0.6))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(f.isLocked ? "Unlock object" : "Lock object")
            .help(f.isLocked ? "Unlock object" : "Lock object")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !model.tool.selects { model.tool = .select }
            model.select(f)
        }
        .listRowBackground(selected ? CP.sky.fill : Color.clear)
        .contextMenu {
            Button { zoom(to: f) } label: { Label("Zoom to object", systemImage: "scope") }
            Button {
                newName = f.name
                renaming = f
            } label: { Label("Rename", systemImage: "pencil") }
            Button {
                if !model.isSelected(f.id) { model.select(f) }
                model.duplicateSelection()
            } label: { Label(model.isMultiSelection && model.isSelected(f.id) ? "Duplicate \(model.selectedIDs.count) objects" : "Duplicate",
                             systemImage: "plus.square.on.square") }
            Button(role: .destructive) {
                if model.isMultiSelection && model.isSelected(f.id) { model.deleteSelection() } else { model.deleteFeature(f.id) }
            } label: { Label(model.isMultiSelection && model.isSelected(f.id) ? "Delete \(model.selectedIDs.count) objects" : "Delete",
                             systemImage: "trash") }
        }
    }

    private func visibilityButton(isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? "eye" : "eye.slash")
                .foregroundStyle(isOn ? CP.ink : CP.inkMuted.opacity(0.6))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Hide" : "Show")
        .help(isOn ? "Hide" : "Show")
    }

    private func zoom(to f: Feature) {
        guard let b = f.bounds else { return }
        model.mapCommand = MapCommand(kind: .zoomToExtent(b))
    }
}
