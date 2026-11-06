import CakraCore
import SwiftUI
import UniformTypeIdentifiers

/// Panel layer: setiap objek vektor (paling atas = digambar paling akhir) plus grup sketsa pensil.
/// Ketuk baris = pilih objek. Mata = tampil/sembunyi (objek tersembunyi tidak ikut export), gembok = kunci.
struct LayerPanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var renaming: Feature?
    @State private var newName = ""
    @State private var reordering = false
    @State private var importingOcad = false

    /// Peta OCAD (.ocd) atau OpenOrienteering Mapper (.omap / .xmap).
    static let mapFileTypes: [UTType] = ["ocd", "omap", "xmap"].map { UTType(filenameExtension: $0, conformingTo: .data) ?? .data }

    private var layers: [Feature] { model.features.reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack {
                Text("\(model.features.count) objek · \(model.strokes.count) stroke")
                    .font(.system(size: 13))
                    .foregroundStyle(CP.inkMuted)
                Spacer()
                Menu {
                    Button { importingOcad = true } label: { Label("Peta OCAD / OOM (.ocd, .omap)…", systemImage: "doc.badge.plus") }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .medium))
                }
                Button(reordering ? "Selesai" : "Urutkan") { reordering.toggle() }
                    .font(.system(size: 13, weight: .medium))
                    .disabled(model.features.count < 2)
            }

            List {
                Section {
                    if layers.isEmpty {
                        Text("Belum ada objek. Pakai Pen tool, Rectangle, atau Ellipse di rail kiri.")
                            .font(.system(size: 13))
                            .foregroundStyle(CP.inkMuted)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(layers) { f in
                        row(f)
                    }
                    .onMove { model.moveFeatures(fromLayerOffsets: $0, toLayerOffset: $1) }
                } header: {
                    Text("Objek vektor")
                }

                Section {
                    HStack(spacing: CP.Space.s) {
                        visibilityButton(isOn: model.sketchVisible) { model.sketchVisible.toggle() }
                        Image(systemName: "pencil.tip").foregroundStyle(CP.inkMuted).frame(width: 18)
                        Text("Sketsa pensil")
                            .font(.system(size: 15))
                            .foregroundStyle(model.sketchVisible ? CP.ink : CP.inkMuted)
                        Spacer()
                        Text(verbatim: "\(model.strokes.count)").font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Sketsa")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(reordering ? .active : .inactive))
        }
        .fileImporter(isPresented: $importingOcad, allowedContentTypes: Self.mapFileTypes) { result in
            if case let .success(url) = result { Task { await model.importOcad(from: url) } }
        }
        .alert("Ganti nama", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nama objek", text: $newName)
            Button("Simpan") {
                if let f = renaming {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.updateFeature(f.id) { $0.name = name }
                }
                renaming = nil
            }
            Button("Batal", role: .cancel) { renaming = nil }
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
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hexString: f.colorHex))
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(f.displayName)
                    .font(.system(size: 15))
                    .foregroundStyle(f.isVisible ? CP.ink : CP.inkMuted)
                    .lineLimit(1)
                Text(f.kind == .point
                     ? "Titik · Ø \(Fmt.mm(f.widthMM)) · \(Int((f.effectiveSizeFactor * 100).rounded()))%"
                     : "\(f.kind.label) · \(f.nodes.count) titik · \(Fmt.mm(f.widthMM))")
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
            .accessibilityLabel(f.isLocked ? "Buka kunci objek" : "Kunci objek")
            .help(f.isLocked ? "Buka kunci objek" : "Kunci objek")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !model.tool.selects { model.tool = .select }
            model.select(f)
        }
        .listRowBackground(selected ? CP.sky.fill : Color.clear)
        .contextMenu {
            Button { zoom(to: f) } label: { Label("Zoom ke objek", systemImage: "scope") }
            Button {
                newName = f.name
                renaming = f
            } label: { Label("Ganti nama", systemImage: "pencil") }
            Button {
                if !model.isSelected(f.id) { model.select(f) }
                model.duplicateSelection()
            } label: { Label(model.isMultiSelection && model.isSelected(f.id) ? "Duplikat \(model.selectedIDs.count) objek" : "Duplikat",
                             systemImage: "plus.square.on.square") }
            Button(role: .destructive) {
                if model.isMultiSelection && model.isSelected(f.id) { model.deleteSelection() } else { model.deleteFeature(f.id) }
            } label: { Label(model.isMultiSelection && model.isSelected(f.id) ? "Hapus \(model.selectedIDs.count) objek" : "Hapus",
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
        .accessibilityLabel(isOn ? "Sembunyikan" : "Tampilkan")
        .help(isOn ? "Sembunyikan" : "Tampilkan")
    }

    private func zoom(to f: Feature) {
        guard let b = f.bounds else { return }
        model.mapCommand = MapCommand(kind: .zoomToExtent(b))
    }
}
