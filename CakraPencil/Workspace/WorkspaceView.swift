import CakraCore
import SwiftUI

/// Layout Mode Meja: top bar, rail alat kiri, dock pena bawah tengah, inspector kanan yang bisa ditutup.
struct WorkspaceView: View {
    @StateObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingExport = false

    var body: some View {
        ZStack {
            MapCanvas(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(model: model, showingExport: $showingExport) {
                    Task {
                        await model.flush()
                        dismiss()
                    }
                }
                HStack(alignment: .top, spacing: 0) {
                    ToolRail(model: model)
                        .padding(CP.Space.m)
                    Spacer(minLength: 0)
                    if model.showsInspector {
                        InspectorPanel(model: model)
                            .frame(width: 300)
                            .padding(CP.Space.m)
                            .transition(.move(edge: .trailing))
                    }
                }
                Spacer(minLength: 0)
                PenDock(model: model)
                    .padding(.bottom, CP.Space.l)
            }

            if let notice = model.notice {
                VStack {
                    Toast(text: notice) { model.notice = nil }
                        .padding(.top, 64)
                    Spacer()
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.showsInspector)
        .sheet(isPresented: $showingExport) {
            ExportSheet(model: model)
        }
        .confirmationDialog("Buka kunci area?", isPresented: $model.confirmUnlock, titleVisibility: .visible) {
            Button("Buka kunci dan geser frame") { model.unlockArea() }
        } message: {
            Text("Sketsa sudah ada. Data di luar frame baru akan disembunyikan saat export, tidak dihapus.")
        }
    }
}

private struct Toast: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(CP.butter.strong)
            .padding(.horizontal, CP.Space.l)
            .padding(.vertical, CP.Space.s)
            .background(CP.butter.fill, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.butter.strong.opacity(0.4)))
            .onTapGesture(perform: onDismiss)
            .task {
                try? await Task.sleep(for: .seconds(4))
                onDismiss()
            }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @ObservedObject var model: WorkspaceModel
    @Binding var showingExport: Bool
    var onClose: () -> Void
    @State private var query = ""

    var body: some View {
        HStack(spacing: CP.Space.m) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel("Kembali ke daftar proyek")

            VStack(alignment: .leading, spacing: 2) {
                Text(model.project.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CP.ink)
                    .lineLimit(1)
                Text(model.project.technicalSummary)
                    .font(CP.mono(12))
                    .foregroundStyle(CP.inkMuted)
                    .onTapGesture(count: 2) { model.mapCommand = MapCommand(kind: .zoomToFrame) }
            }
            .frame(minWidth: 140, alignment: .leading)

            HStack(spacing: CP.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(CP.inkMuted)
                TextField("Cari tempat, lat, lon, atau UTM", text: $query)
                    .font(.system(size: 15))
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await model.search(query) } }
            }
            .padding(.horizontal, CP.Space.m)
            .frame(maxWidth: 380, minHeight: 36)
            .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))

            Spacer(minLength: 0)

            SaveBadge(state: model.saveState)

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(ToolButtonStyle())
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityLabel("Undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(ToolButtonStyle())
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityLabel("Redo")
            Button { model.showsInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(ToolButtonStyle(isActive: model.showsInspector))
                .accessibilityLabel("Inspector")
            Button("Export") { showingExport = true }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.frame == nil)
                .keyboardShortcut("e", modifiers: .command)
        }
        .padding(.horizontal, CP.Space.m)
        .padding(.vertical, CP.Space.s)
        .background(CP.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(CP.line).frame(height: 1) }
    }
}

private struct SaveBadge: View {
    let state: SaveState

    var body: some View {
        switch state {
        case .saved:
            Label("Tersimpan", systemImage: "checkmark").foregroundStyle(CP.sage.strong).font(.system(size: 13))
        case .saving:
            Label("Menyimpan", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(CP.inkMuted).font(.system(size: 13))
        case let .failed(msg):
            Label("Gagal simpan", systemImage: "exclamationmark.triangle")
                .foregroundStyle(CP.rose.strong).font(.system(size: 13))
                .help(msg)
        }
    }
}

// MARK: - Rail alat

private struct ToolRail: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(spacing: CP.Space.xs) {
            ForEach(Tool.allCases) { tool in
                Button { model.tool = tool } label: { Image(systemName: tool.symbol) }
                    .buttonStyle(ToolButtonStyle(isActive: model.tool == tool))
                    .disabled(tool == .area && model.project.areaLocked)
                    .keyboardShortcut(KeyEquivalent(tool.shortcut), modifiers: [])
                    .accessibilityLabel(tool.label)
            }
            Rectangle().fill(CP.line).frame(width: 28, height: 1).padding(.vertical, CP.Space.xs)
            Button { model.mapCommand = MapCommand(kind: .zoomToFrame) } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                .buttonStyle(ToolButtonStyle())
                .accessibilityLabel("Zoom ke frame")
            Button { model.mapCommand = MapCommand(kind: .followUser) } label: { Image(systemName: "location") }
                .buttonStyle(ToolButtonStyle())
                .accessibilityLabel("Zoom ke GPS")
        }
        .padding(CP.Space.xs)
        .cpPanel()
    }
}

// MARK: - Dock pena

private struct PenDock: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        HStack(spacing: CP.Space.m) {
            ForEach(PenPreset.isom) { preset in
                let active = model.pen.colorHex == preset.colorHex
                Button {
                    model.pen = preset
                    if !model.tool.draws { model.tool = .pen }
                } label: {
                    Circle()
                        .fill(Color(hexString: preset.colorHex))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(CP.paper, lineWidth: 2))
                        .overlay(Circle().strokeBorder(active ? CP.peach.strong : CP.line, lineWidth: active ? 2 : 1).padding(-3))
                        .frame(width: CP.hitTarget, height: CP.hitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pena \(preset.name) \(Fmt.mm(preset.widthMM))")
            }

            Rectangle().fill(CP.line).frame(width: 1, height: 28)

            Button { model.setPenWidth(model.pen.widthMM - 0.01) } label: { Image(systemName: "minus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("[", modifiers: [])
                .accessibilityLabel("Kurangi tebal")
            Slider(value: Binding(get: { model.pen.widthMM }, set: { model.setPenWidth($0) }),
                   in: PenPreset.widthRange)
                .frame(width: 140)
                .accessibilityLabel("Tebal garis")
            Button { model.setPenWidth(model.pen.widthMM + 0.01) } label: { Image(systemName: "plus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("]", modifiers: [])
                .accessibilityLabel("Tambah tebal")
            Text(Fmt.mm(model.pen.widthMM))
                .font(CP.mono(15, weight: .medium))
                .foregroundStyle(CP.ink)
                .frame(width: 76, alignment: .trailing)

            Rectangle().fill(CP.line).frame(width: 1, height: 28)

            Toggle(isOn: $model.fingerDraws) {
                Image(systemName: "hand.point.up.left")
            }
            .toggleStyle(.button)
            .tint(CP.peach.strong)
            .accessibilityLabel("Jari ikut menggambar")
            .help("Untuk iPad tanpa Pencil atau simulator: satu jari menggambar, dua jari navigasi")
        }
        .padding(.horizontal, CP.Space.m)
        .padding(.vertical, CP.Space.xs)
        .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(CP.peach.fill, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }
}
