import CakraCore
import SwiftUI
import UniformTypeIdentifiers

/// Two work stages:
/// 1. Select Area: the A4 frame stays at the screen center; the user searches for a location, pans/zooms the map, then Use this area (locks the area).
/// 2. Sketch (Desk Mode): only the locked area is shown; tool rail on the left, pen dock at the bottom, inspector on the right.
struct WorkspaceView: View {
    @StateObject var model: WorkspaceModel
    @EnvironmentObject private var symbols: SymbolLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var showingExport = false
    @State private var savingFile: ProjectFileDocument?
    /// Bottom edge of the toolbar band (Mac and iPad); the map canvas starts below it (the frame isn't covered).
    @State private var bandBottom: CGFloat = 0

    /// iPad field mode is a full-screen map without the band.
    private var mapTopInset: CGFloat { model.fieldMode && !CP.isMac && !model.showsCoursePlanner ? 0 : bandBottom }

    /// Write the latest changes, then wrap the project package into a .cpencil file.
    private func saveFile() {
        Task {
            await model.flush()
            let url = model.url
            do {
                let data = try await Task.detached(priority: .userInitiated) { try ProjectArchive.pack(packageAt: url) }.value
                savingFile = ProjectFileDocument(data: data)
            } catch {
                model.notice = "Couldn't prepare the project file: \(error.localizedDescription)"
            }
        }
    }

    /// Compass in the right corner of the toolbar band.
    private var bandCompass: some View {
        DigitalCompass(model: model, live: model.live, embedded: true).modifier(BandCornerPadding())
    }

    var body: some View {
        ZStack {
            MapCanvas(model: model, role: .workspace)
                .padding(.top, mapTopInset)
                .ignoresSafeArea(edges: mapTopInset > 0 ? [.bottom, .horizontal] : .all)

            // While the Course page is open, the workspace UI below it isn't rendered (the layers panel with hundreds of
            // objects was recomputed on every change; performance test: Course panel change 190 ms → a few ms).
            if model.fieldMode && !model.showsCoursePlanner && !CP.isMac {
                // Field mode (iPad): full-screen map, big high-contrast buttons, screen kept on.
                FieldModeOverlay(model: model, recorder: model.recorder)
            } else if !model.showsCoursePlanner {
            VStack(spacing: 0) {
                TopBar(model: model, showingExport: $showingExport, onSaveFile: saveFile) {
                    Task {
                        await model.flush()
                        dismiss()
                    }
                }
                .zIndex(10)

                if model.isSelectingArea {
                    // The select-area panel + map controls are attached to the top band (Mac and iPad).
                    AreaPanel(model: model)
                    .padding(.horizontal, CP.Space.m)
                    .padding(.vertical, CP.Space.s)
                    .modifier(MacBand())
                    .modifier(BandBottomReader(space: "workspace"))
                    // Place search + zoom floating on the map, right below the panel (suggestions open over the map).
                    SelectAreaSearchBar(model: model)
                        .padding(.top, CP.Space.m)
                        .padding(.horizontal, CP.Space.m)
                        .zIndex(5)
                    Spacer(minLength: 0)
                } else {
                    // The toolbar band sits below the top bar (like OCAD), on Mac and iPad: tools + map controls + pens
                    // in one row (narrow window / iPad portrait: two rows, scrolling sideways if needed), then the
                    // contextual bar row if any. The right panel below it.
                    VStack(alignment: .leading, spacing: 0) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: CP.Space.s) {
                                ToolRail(model: model, horizontal: true, showsCompass: false)
                                BandSeparator()
                                PenDock(model: model)
                                Spacer(minLength: 0)
                                bandCompass
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    ToolRail(model: model, horizontal: true, showsCompass: false)
                                    Spacer(minLength: 0)
                                    bandCompass
                                }
                                Rectangle().fill(CP.line).frame(height: 1)
                                HStack { PenDock(model: model); Spacer(minLength: 0) }
                            }
                            // iPad portrait: drawing tools on the first row, map controls + pens on the second (that row
                            // scrolls sideways only if it still doesn't fit).
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    ToolRail(model: model, horizontal: true, showsCompass: false, part: .tools)
                                    Spacer(minLength: 0)
                                    bandCompass
                                }
                                Rectangle().fill(CP.line).frame(height: 1)
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: CP.Space.s) {
                                        ToolRail(model: model, horizontal: true, showsCompass: false, part: .mapControls)
                                        BandSeparator()
                                        PenDock(model: model)
                                        Spacer(minLength: 0)
                                    }
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: CP.Space.s) {
                                            ToolRail(model: model, horizontal: true, showsCompass: false, part: .mapControls)
                                            BandSeparator()
                                            PenDock(model: model)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, CP.Space.s)
                        .padding(.vertical, 2)
                        VectorToolBar(model: model)
                    }
                    .modifier(MacBand())
                    .modifier(BandBottomReader(space: "workspace"))
                    // The right panel is attached full height on the right side, from below the band to the bottom of the window.
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        // iPad: tap or swipe the handle to hide / show the panel.
                        if !CP.isMac && model.symbolGuide == nil {
                            PanelEdgeHandle(isOpen: $model.showsInspector)
                        }
                        if model.symbolGuide != nil {
                            SymbolGuidePanel(model: model)
                                .frame(width: CP.isMac ? 380 : 320)
                                .modifier(SidePanelChrome(maxHeight: .infinity, minHeight: 280))
                                .transition(.move(edge: .trailing))
                        } else if model.showsInspector {
                            InspectorPanel(model: model)
                                .frame(width: CP.isMac ? 300 : 280)
                                .clipped()
                                .transition(.move(edge: .trailing))
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            // The keyboard (e.g. symbol search) covers the dock instead of compressing the layout: without this the height of
            // rail + panel exceeds the remaining screen and the top bar is pushed off screen.
            .ignoresSafeArea(.keyboard)

            }

            // Track recording indicator: stays visible with the side panel closed (iPad).
            if !model.showsCoursePlanner && !model.fieldMode {
                RecordingBadge(model: model, recorder: model.recorder)
            }

            // Drawing a field sketch note (workspace and field mode): Undo stroke, Clear, Cancel, Done.
            if model.fieldSketch != nil && !model.showsCoursePlanner {
                FieldSketchBar(model: model)
            }

            // iPad without a license: view-only banner (pan, zoom, export to PDF).
            if model.isReadOnly && !model.showsCoursePlanner {
                VStack {
                    Spacer()
                    // Above the bottom dock, clear of the side panels.
                    ViewOnlyBanner()
                        .padding(.bottom, CP.Space.xl)
                }
            }

            if let notice = model.notice, !model.showsCoursePlanner {
                VStack {
                    // The toolbar is at the top, so messages appear at the bottom.
                    Spacer()
                    Toast(text: notice) { model.notice = nil }
                        .padding(.bottom, CP.Space.xl)
                }
            }
        }
        .coordinateSpace(name: "workspace")
        .onPreferenceChange(BandBottomKey.self) { bandBottom = $0 }
        .animation(.easeOut(duration: 0.18), value: model.showsInspector)
        .animation(.easeOut(duration: 0.18), value: model.symbolGuide == nil)
        .animation(.easeOut(duration: 0.18), value: model.isSelectingArea)
        .background { KeyboardNavigation(model: model) }
        .onAppear { model.symbolLookup = { [weak symbols, weak model] code, name in
            guard let symbols, let sheet = model?.project.sheet else { return nil }
            // Same code + name first (objects from another set keep their symbol), best set for the map (scale and
            // standard: ISInOM on indoor maps) otherwise.
            return symbols.symbol(code: code, name: name, sheet: sheet)
        } }
        #if DEBUG
        // For screenshots/UI tests: `-cp-import-ocd <file>` imports a file from the app's Documents folder.
        .task {
            let args = ProcessInfo.processInfo.arguments
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            if let i = args.firstIndex(of: "-cp-import-ocd"), i + 1 < args.count {
                await model.importOcad(from: docs.appendingPathComponent(args[i + 1]))
            }
            // `-cp-import-gpx <file>` imports field tracks / waypoints from a GPX file in Documents.
            if let i = args.firstIndex(of: "-cp-import-gpx"), i + 1 < args.count {
                await model.importGPX(from: docs.appendingPathComponent(args[i + 1]))
            }
            // `-cp-zoom-to fx,fy,spanM`: center the map at a point given as fractions of the frame, showing spanM meters
            // (screenshots).
            if let i = args.firstIndex(of: "-cp-zoom-to"), i + 1 < args.count, let f = model.frame, let zone = model.zone {
                let v = args[i + 1].split(separator: ",").compactMap { Double($0) }
                if v.count == 3 {
                    try? await Task.sleep(for: .seconds(2.5))
                    let p = Point2D(x: f.origin.x + f.widthM * v[0], y: f.origin.y + f.heightM * v[1])
                    model.mapCommand = MapCommand(kind: .center(zone.unproject(p), spanM: v[2]))
                }
            }
            // `-cp-sample-ornaments`: one area of each patterned symbol and lines with decorations (visual check of the
            // ISOM patterns / tags in UI tests).
            if args.contains("-cp-sample-ornaments"), let f = model.frame {
                try? await Task.sleep(for: .seconds(1.5))
                if let lookup = model.symbolLookup {
                    let cell = model.project.sheet.groundMeters(forPaperMM: 9)
                    let x0 = f.origin.x + f.widthM * 0.2, y0 = f.origin.y + f.heightM * 0.7
                    let areas = ["308.0", "402.0", "404.0", "407.0", "409.0", "412.0", "413.0", "208.0", "210.0", "213.0", "414.0", "709.0"]
                    for (i, code) in areas.enumerated() {
                        guard let s = lookup(code, nil), s.kind == .area else { continue }
                        let x = x0 + Double(i % 4) * cell, y = y0 - Double(i / 4) * cell, w = cell * 0.85
                        let nodes = [(x, y), (x + w, y), (x + w, y - w), (x, y - w)].map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) }
                        model.addFeature(Feature(kind: .area, colorHex: s.colorHex, widthMM: s.drawingWidthMM, nodes: nodes,
                                                 symbolCode: s.code, symbolName: s.name))
                    }
                    let lines = ["104.0", "201.0", "516.0", "513.1", "518.0", "528.0", "512.0", "510.0"]
                    for (i, code) in lines.enumerated() {
                        guard let s = lookup(code, nil), s.kind == .line else { continue }
                        let y = y0 - 3.4 * cell - Double(i) * cell * 0.45
                        var feat = Feature(kind: .line, colorHex: s.colorHex, widthMM: s.drawingWidthMM,
                                           nodes: [BezierNode(point: Point2D(x: x0, y: y)), BezierNode(point: Point2D(x: x0 + 3.6 * cell, y: y))],
                                           symbolCode: s.code, symbolName: s.name)
                        if let style = s.lineStyle { feat.apply(style) }
                        model.addFeature(feat)
                    }
                    model.selectedFeatureID = nil
                }
            }
            // `-cp-sample-photo-note`: a field note with a generated photo (camera facing NE) near the frame center.
            if args.contains("-cp-sample-photo-note"), let f = model.frame {
                let img = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { ctx in
                    UIColor(red: 0.35, green: 0.5, blue: 0.3, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
                    UIColor(white: 0.45, alpha: 1).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 380, y: 300, width: 440, height: 360))
                    ("Sample field photo" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 56), .foregroundColor: UIColor.white])
                }
                if let data = img.jpegData(compressionQuality: 0.7) {
                    let c = Point2D(x: f.origin.x + f.widthM * 0.4, y: f.origin.y + f.heightM * 0.6)
                    model.addFieldNote(category: .boulder, text: "Boulder with photo", photos: [data], heading: 45, atGPS: false, position: c)
                }
            }
            // `-cp-field-coverage`: tracks, notes and survey coverage shading shown (screenshots).
            if args.contains("-cp-field-coverage") { model.setFieldItemsVisible(Set(model.field.tracks.map(\.id) + model.field.notes.map(\.id)), true); model.updateField { $0.showCoverage = true } }
            // `-cp-hide-field`: tracks, notes and coverage hidden (screenshots of the drawing).
            if args.contains("-cp-hide-field") { model.setFieldItemsVisible(Set(model.field.tracks.map(\.id) + model.field.notes.map(\.id)), false); model.updateField { $0.showCoverage = false } }
            // `-cp-sample-sketch-note`: a sketch note (a loop around a thicket, with a path stroke) near the frame center.
            if args.contains("-cp-sample-sketch-note"), let f = model.frame {
                let c = Point2D(x: f.origin.x + f.widthM * 0.55, y: f.origin.y + f.heightM * 0.45), r = min(f.widthM, f.heightM) * 0.08
                let loop = (0...36).map { i -> Point2D in
                    let a = Double(i) / 36 * 2 * .pi
                    return Point2D(x: c.x + r * cos(a) * (1 + 0.15 * sin(3 * a)), y: c.y + r * 0.7 * sin(a))
                }
                let path = [Point2D(x: c.x - 2.2 * r, y: c.y - 1.4 * r), Point2D(x: c.x - 1.2 * r, y: c.y - 0.9 * r), Point2D(x: c.x - r * 0.9, y: c.y)]
                model.addFieldNote(category: .vegetation, text: "Thicket, fight", photos: [], heading: nil, atGPS: false,
                                   position: FieldNote.sketchAnchor([loop, path]), sketch: [loop, path])
            }
            // `-cp-export-field <file>` / `-cp-import-field <file>`: field data to / from Documents (UI tests).
            if let i = args.firstIndex(of: "-cp-export-field"), i + 1 < args.count {
                try? await Task.sleep(for: .seconds(1))
                await model.exportFieldData(newOnly: false, saveTo: docs.appendingPathComponent(args[i + 1]))
            }
            if let i = args.firstIndex(of: "-cp-import-field"), i + 1 < args.count {
                await model.importFieldData(from: docs.appendingPathComponent(args[i + 1]))
            }
            // `-cp-field-report <file>`: write the field report PDF to Documents (after the other launch steps).
            if let i = args.firstIndex(of: "-cp-field-report"), i + 1 < args.count {
                try? await Task.sleep(for: .seconds(2))
                await model.exportFieldReport(saveTo: docs.appendingPathComponent(args[i + 1]))
            }
            // `-cp-open-guide`: open the symbol guide for the active symbol (screenshots / UI tests).
            if args.contains("-cp-open-guide") {
                try? await Task.sleep(for: .seconds(1))
                model.toggleSymbolGuide()
            }
            // `-cp-import-course <file>`: same as Import course on the Course page.
            if let i = args.firstIndex(of: "-cp-import-course"), i + 1 < args.count {
                // With -cp-open-course: import once the Course page is up, like pressing its Import course button.
                if args.contains("-cp-open-course") { try? await Task.sleep(for: .seconds(1.5)) }
                await model.importCourseFile(from: docs.appendingPathComponent(args[i + 1]))
            }
            // `-cp-reselect-area`: press "Reselect area" (tests Cancel / basemap while reselecting).
            if args.contains("-cp-reselect-area"), model.project.areaLocked { model.unlockArea() }
            // `-cp-skip-area-basemap <file>`: skip area selection using Documents/<file> (GeoTIFF).
            if let i = args.firstIndex(of: "-cp-skip-area-basemap"), i + 1 < args.count {
                await model.skipAreaSelection(withBasemap: docs.appendingPathComponent(args[i + 1]))
            }
            // `-cp-import-basemap <file>`: import Documents/<file> (GeoTIFF) as an image basemap.
            if let i = args.firstIndex(of: "-cp-import-basemap"), i + 1 < args.count {
                await model.importBasemapImage(from: docs.appendingPathComponent(args[i + 1]))
            }
            // `-cp-move-frame-to-basemap`: accept "Move frame to image" (tests basemap display).
            if args.contains("-cp-move-frame-to-basemap"), model.project.basemapImage != nil, !model.basemapImageTouchesFrame {
                model.confirmMoveFrameToBasemap = false
                model.moveFrameToBasemapImage()
            }
            // `-cp-use-symbol <number>` activates a symbol from the built-in set (e.g. 417000).
            if let i = args.firstIndex(of: "-cp-use-symbol"), i + 1 < args.count, let n = Int(args[i + 1]),
               let sym = symbols.builtInSet?.symbols.first(where: { $0.number == n }) {
                model.useSymbol(sym)
            }
            // `-cp-download-contours` downloads the built-in contours for the frame.
            if args.contains("-cp-download-contours") { await model.downloadBuiltInContours() }
            // `-cp-zoom-points` zooms to all point objects; `-cp-zoom-last` zooms to the last 3 objects.
            if args.contains("-cp-zoom-points") || args.contains("-cp-zoom-last") {
                let targets = args.contains("-cp-zoom-last") ? Array(model.features.suffix(3)) : model.features.filter { $0.kind == .point }
                let pts = targets.flatMap { $0.nodes.map(\.point) }
                if var r = Rect2D(points: pts) {
                    r = r.insetBy(-15)
                    try? await Task.sleep(for: .seconds(1.5))
                    model.mapCommand = MapCommand(kind: .zoomToExtent(r))
                }
            }
            // `-cp-import-symbols` imports every .ocd in Documents/SymbolInbox as a symbol set.
            if args.contains("-cp-import-symbols") {
                let inbox = docs.appendingPathComponent("SymbolInbox")
                let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
                await symbols.importOcad(files.filter { $0.pathExtension == "ocd" })
            }
        }
        #endif
        #if DEBUG
        // `-cp-save-file <name>`: save the project to Documents/<name>.cpencil without a dialog (iPad ↔ Mac test).
        .task {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-cp-save-file"), i + 1 < args.count else { return }
            await model.flush()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            if let data = try? ProjectArchive.pack(packageAt: model.url) {
                try? data.write(to: docs.appendingPathComponent(args[i + 1]).appendingPathExtension(ProjectArchive.fileExtension))
            }
        }
        #endif
        .onChange(of: model.exportContoursOnly) { _, on in if on { showingExport = true } }
        #if DEBUG
        // Screenshots: `-cp-show-export` opens Export (the Course page opens its own with -cp-open-course).
        .task {
            let args = ProcessInfo.processInfo.arguments
            guard args.contains("-cp-show-export"), !args.contains("-cp-open-course") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            showingExport = true
        }
        #endif
        // Save the .cpencil project file (iPad: Files; Mac: Finder dialog); can be imported on both iPad and Mac.
        .fileExporter(isPresented: Binding(get: { savingFile != nil }, set: { if !$0 { savingFile = nil } }),
                      document: savingFile, contentType: .cakraProject, defaultFilename: projectFileName(model.project.name)) { result in
            switch result {
            case .success: model.notice = "Project file saved."
            case let .failure(error): model.notice = "Couldn't save the file: \(error.localizedDescription)"
            }
            savingFile = nil
        }
        .sheet(isPresented: $showingExport, onDismiss: { model.exportContoursOnly = false }) {
            ExportSheet(model: model, mode: model.exportContoursOnly ? .contours : .sheet)
        }
        .fullScreenCover(isPresented: Binding(get: { model.showsCoursePlanner }, set: { if !$0 { model.closeCoursePlanner() } })) {
            CoursePlannerView(model: model)
                .environmentObject(symbols)
        }
        // Course file imported from the Layers panel (the Course page shows its own copy of this alert).
        .alert("Courses outside this map", isPresented: Binding(get: { model.courseImportOutside != nil && !model.showsCoursePlanner },
                                                              set: { if !$0 { model.courseImportOutside = nil } })) {
            Button("Undo import", role: .destructive) { model.undo() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text(model.courseImportOutside ?? "")
        }
        .alert("Basemap outside the frame", isPresented: $model.confirmMoveFrameToBasemap) {
            Button("Move frame to image") { model.moveFrameToBasemapImage() }
            Button("Leave it", role: .cancel) {}
        } message: {
            Text("The image doesn't touch the map frame, so it isn't visible (the area outside the frame is masked). Move the frame to the center of the image? Scale and existing objects don't change; this can be undone.")
        }
        .confirmationDialog("Unlock area?", isPresented: $model.confirmUnlock, titleVisibility: .visible) {
            Button("Unlock and reselect area") { model.unlockArea() }
        } message: {
            Text("Sketches already exist. Data outside the new frame will be hidden on export, not deleted.")
        }
    }
}

struct Toast: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        Text(text)
            .font(.system(size: CP.fs(15)))
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

/// Keyboard shortcuts without on-screen buttons: arrows = pan the map, ⌘= / ⌘− = zoom.
private struct KeyboardNavigation: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        ZStack {
            key(.leftArrow, .pan(dx: -1, dy: 0))
            key(.rightArrow, .pan(dx: 1, dy: 0))
            key(.upArrow, .pan(dx: 0, dy: -1))
            key(.downArrow, .pan(dx: 0, dy: 1))
            key("=", .zoom(2), modifiers: .command)
            key("-", .zoom(0.5), modifiers: .command)
            // Symbol guide (⇧⌘/).
            Button("") { model.toggleSymbolGuide() }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            // Select all (⌘A) without a button.
            Button("") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func key(_ k: KeyEquivalent, _ kind: MapCommand.Kind, modifiers: EventModifiers = []) -> some View {
        Button("") { model.mapCommand = MapCommand(kind: kind) }
            .keyboardShortcut(k, modifiers: modifiers)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @ObservedObject var model: WorkspaceModel
    @Binding var showingExport: Bool
    var onSaveFile: () -> Void = {}
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: CP.Space.m) {
            // OCCA mark in the top-left corner of every page.
            AppMark().frame(width: 26, height: 26).accessibilityHidden(true)
            Button(action: onClose) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(ToolButtonStyle(compact: true))
            .accessibilityLabel("Back to project list")
            .help("Back to project list")

            VStack(alignment: .leading, spacing: 2) {
                Text(model.project.name)
                    .font(.system(size: CP.fs(15), weight: .semibold))
                    .foregroundStyle(CP.ink)
                    .lineLimit(1)
                Text(model.project.technicalSummary)
                    .font(CP.mono(12))
                    .lineLimit(1)
                    .foregroundStyle(CP.inkMuted)
                    .onTapGesture(count: 2) { model.mapCommand = MapCommand(kind: .zoomToFrame) }
            }
            .frame(minWidth: 140, alignment: .leading)

            Spacer(minLength: 0)

            // Auto-save status: only once there is drawing to save (not on the Select map area page, where the frame
            // settings save by themselves and the place search lives in the area panel).
            if !model.isSelectingArea {
                SaveBadge(state: model.saveState)
            }

            if !model.isSelectingArea {
                // Grouped: history (undo/redo) · Course · view and file (panel/save) · Export.
                ButtonGroup {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(GroupedButtonStyle())
                        .disabled(!model.canUndo)
                        .keyboardShortcut("z", modifiers: .command)
                        .accessibilityLabel("Undo")
                        .help("Undo (⌘Z)")
                    GroupDivider()
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .buttonStyle(GroupedButtonStyle())
                        .disabled(!model.canRedo)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .accessibilityLabel("Redo")
                        .help("Redo (⇧⌘Z)")
                }
                Button { model.openCoursePlanner() } label: {
                    HStack(spacing: 7) {
                        ControlFlagIcon(color: CP.lavender.strong).frame(width: 14, height: 14)
                        Text("Course")
                    }
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(TintedButtonStyle(tone: CP.lavender))
                .keyboardShortcut("k", modifiers: .command)
                .accessibilityLabel("Open Course Settings")
                .help("Open Course Settings (⌘K)")
                ButtonGroup {
                    Button { model.showsInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                        .buttonStyle(GroupedButtonStyle(isActive: model.showsInspector))
                        .accessibilityLabel("Inspector")
                        .help("Show/hide the right panel")
                    GroupDivider()
                    Button(action: onSaveFile) { Image(systemName: "square.and.arrow.down") }
                        .buttonStyle(GroupedButtonStyle())
                        .keyboardShortcut("s", modifiers: .command)
                        .accessibilityLabel("Save project file")
                        .help("Save .occa project file — opens on iPad and Mac (⌘S)")
                }
                Button("Export") { showingExport = true }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
        .padding(.horizontal, CP.Space.m)
        .padding(.vertical, CP.Space.s)
        .background(CP.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(CP.line).frame(height: 1) }
    }
}

struct SaveBadge: View {
    let state: SaveState

    var body: some View {
        badge
            .lineLimit(1)
            .fixedSize()   // doesn't wrap to two lines when the top bar is narrow (iPad portrait)
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .saved:
            Label("Saved", systemImage: "checkmark").foregroundStyle(CP.sage.strong).font(.system(size: CP.fs(13)))
        case .saving:
            Label("Saving", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(CP.inkMuted).font(.system(size: CP.fs(13)))
        case let .failed(msg):
            Label("Save failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(CP.rose.strong).font(.system(size: CP.fs(13)))
                .help(msg)
        }
    }
}

// MARK: - Select Area

/// Select-area panel: floating at the bottom (iPad) or attached to the top band (Mac).
private struct AreaChrome: ViewModifier {
    @Environment(\.docked) private var docked

    func body(content: Content) -> some View {
        if docked {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
                .padding(CP.Space.l)
                .frame(maxWidth: 900)
                .cpPanel()
        }
    }
}

/// Select map area: place search with zoom in / zoom out / fit next to it, floating at the top of the map.
private struct SelectAreaSearchBar: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        HStack(spacing: CP.Space.s) {
            LocationSearchField(model: model, prominent: true)
                .frame(maxWidth: 520)
            HStack(spacing: 2) {
                zoom("plus.magnifyingglass", "Zoom in") { model.mapCommand = MapCommand(kind: .zoom(2)) }
                zoom("minus.magnifyingglass", "Zoom out") { model.mapCommand = MapCommand(kind: .zoom(0.5)) }
                zoom("arrow.down.right.and.arrow.up.left", "Fit frame") { model.mapCommand = MapCommand(kind: .zoomToFrame) }
            }
            .padding(2)
            .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
        }
        .frame(maxWidth: .infinity)
    }

    private func zoom(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(GroupedButtonStyle())
            .accessibilityLabel(label)
            .help(label)
    }
}

private struct AreaPanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var importingBasemap = false
    @Environment(\.docked) private var docked

    private var sheet: SheetSpec { model.project.sheet }

    var body: some View {
        Group {
            if docked { macBody } else { padBody }
        }
        // Skip area selection: the area is taken from an already georeferenced GeoTIFF basemap.
        .fileImporter(isPresented: $importingBasemap, allowedContentTypes: [.tiff]) { result in
            if case let .success(url) = result { Task { await model.skipAreaSelection(withBasemap: url) } }
        }
        .modifier(AreaChrome())
    }

    /// Mac (top toolbar band): title + size and map controls in the first row, a one-line hint,
    /// then settings aligned left and actions aligned right.
    private var macBody: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack(alignment: .center, spacing: CP.Space.m) {
                Text("Select map area")
                    .font(.system(size: CP.fs(17), weight: .semibold))
                    .foregroundStyle(CP.ink)
                Text(summary)
                    .font(CP.mono(13))
                    .foregroundStyle(CP.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text("Pan and zoom the map until the area you want to map is inside the frame (the frame stays centered), or skip by uploading a GeoTIFF basemap.")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CP.Space.m) {
                    settings
                    Spacer(minLength: CP.Space.l)
                    actions
                }
                VStack(alignment: .leading, spacing: CP.Space.s) {
                    HStack(spacing: CP.Space.m) { settings }
                    HStack(spacing: CP.Space.m) {
                        Spacer(minLength: 0)
                        actions
                    }
                }
            }
        }
        .padding(.vertical, CP.Space.xs)
    }

    private var padBody: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Select map area")
                    .font(.system(size: CP.fs(17), weight: .semibold))
                    .foregroundStyle(CP.ink)
                Spacer()
                Text(summary)
                    .font(CP.mono(13))
                    .foregroundStyle(CP.inkMuted)
            }
            Text("Search for a location in the field at the top of the map, then pan and zoom the map until the area you want to map is inside the frame. The frame stays at the center of the screen. Already have georeferenced imagery? Skip and upload a GeoTIFF basemap — the frame is centered on the image automatically.")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            // One row if it fits; narrow screen (iPad portrait): actions drop to a second row, aligned right.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CP.Space.m) {
                    settings
                    Spacer(minLength: 0)
                    actions
                }
                VStack(alignment: .leading, spacing: CP.Space.s) {
                    HStack(spacing: CP.Space.m) { settings }
                    HStack(spacing: CP.Space.m) {
                        Spacer(minLength: 0)
                        actions
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var settings: some View {
        Segmented("Orientation", selection: Binding(get: { sheet.orientation }, set: { o in model.updateSheet { $0.orientation = o } }),
                  [.init(.portrait, "Portrait"), .init(.landscape, "Landscape")])
        .frame(width: 220)

        Picker("Scale", selection: Binding(get: { sheet.scaleDenominator }, set: { s in model.updateSheet { $0.scaleDenominator = s } })) {
            ForEach(FreeLimits.pickableScales(current: sheet.scaleDenominator, indoor: sheet.isIndoor), id: \.self) { Text(verbatim: "1:\($0)").tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Map scale")

        Toggle("Indoor", isOn: Binding(get: { sheet.isIndoor }, set: { model.setIndoor($0) }))
            .toggleStyle(.button)
            .tint(CP.sage.strong)
            .fixedSize()
            .accessibilityIdentifier("areaIndoor")
            .help("Indoor map (ISInOM 6.7.3, base 1:700): indoor scales, symbols and course sizes")

        Picker("Margin", selection: Binding(get: { sheet.marginMM }, set: { m in model.updateSheet { $0.marginMM = m } })) {
            ForEach(MapPresets.marginsMM, id: \.self) { Text("Margin \(Fmt.mm($0, decimals: 0))").tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Print margin")

        Picker("Corner snap", selection: Binding(get: { model.project.snapStepM }, set: { model.setSnapStep($0) })) {
            ForEach(MapPresets.snapStepsM, id: \.self) { Text(verbatim: $0 == 0 ? "Snap off" : "Snap \($0) m").tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Snap frame corners to meter multiples")
    }

    @ViewBuilder
    private var actions: some View {
        if model.project.areaBackup != nil {
            // Reselected area not locked yet: go back to the previous area (and view).
            Button { model.cancelReselectArea() } label: {
                Label("Cancel", systemImage: "arrow.uturn.backward")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityIdentifier("cancelReselectArea")
            .help("Cancel reselecting area: go back to the previous area (Esc)")
        }
        // Same size for all: secondary actions, then the main one (Fit frame is next to the place search).

        Button { importingBasemap = true } label: {
            Label("Use a GeoTIFF instead", systemImage: "photo.on.rectangle.angled")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(SecondaryButtonStyle(compact: true))
        .accessibilityIdentifier("skipAreaWithBasemap")
        .help("Skip area selection: upload a georeferenced GeoTIFF; the frame is centered on the image and the area is locked")

        Button { model.lockArea() } label: {
            Label("Use this area", systemImage: "checkmark")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(PrimaryButtonStyle(compact: true))
        .disabled(model.frame == nil)
        .accessibilityIdentifier("lockArea")
        .help("Lock the frame here and start mapping (⌘↩). Change it later with Reselect area.")
        .keyboardShortcut(.return, modifiers: .command)
    }

    private var summary: String {
        var parts = ["\(Fmt.meters(sheet.groundWidthM, decimals: 0)) × \(Fmt.meters(sheet.groundHeightM, decimals: 0))"]
        let d = sheet.pixelDimensions(dpi: model.project.sketchDPI)
        parts.append(Fmt.pixels(d.width, d.height))
        if let zone = model.zone { parts.append(zone.label) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Map controls (digital compass + zoom)

struct MapControls: View {
    @ObservedObject var model: WorkspaceModel
    /// Mac: one row in the top toolbar band.
    var horizontal = false
    /// Mac: compass in the right corner of the band (placed separately).
    var showsCompass = true
    /// My location button (with its separator). Off while selecting the map area.
    var showsLocation = true

    /// Column width = tool rail width (44 pt button + padding), so map controls line up below the rail.
    static let width = CP.hitTarget + 2 * CP.Space.xs

    var body: some View {
        if horizontal {
            HStack(spacing: CP.Space.xs) {
                zoomButton("plus.magnifyingglass", factor: 2, label: "Zoom in")
                zoomButton("minus.magnifyingglass", factor: 0.5, label: "Zoom out")
                FitMapButton(model: model)
                if showsLocation || showsCompass { BandSeparator().padding(.horizontal, CP.Space.xs) }
                if showsLocation { LocationButton(model: model, live: model.live, embedded: true) }
                if showsCompass { DigitalCompass(model: model, live: model.live, embedded: true).modifier(BandCornerPadding()) }
            }
            .fixedSize()
        } else {
            vertical
        }
    }

    private var vertical: some View {
        VStack(spacing: CP.Space.s) {
            if showsCompass { DigitalCompass(model: model, live: model.live) }
            VStack(spacing: 0) {
                zoomButton("plus.magnifyingglass", factor: 2, label: "Zoom in")
                Rectangle().fill(CP.line).frame(width: 28, height: 1)
                zoomButton("minus.magnifyingglass", factor: 0.5, label: "Zoom out")
                Rectangle().fill(CP.line).frame(width: 28, height: 1)
                FitMapButton(model: model)
            }
            .padding(CP.Space.xs)
            .cpPanel()
            if showsLocation { LocationButton(model: model, live: model.live) }
        }
        .frame(width: Self.width)
    }

    private func zoomButton(_ icon: String, factor: Double, label: String) -> some View {
        Button { model.mapCommand = MapCommand(kind: .zoom(factor)) } label: { Image(systemName: icon) }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel(label)
            .help(label)
    }
}

/// Show/hide the north lines (vertical grid lines) on the map; highlighted while shown.
private struct NorthLinesButton: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        let on = model.project.grid.isEnabled
        Button { model.toggleNorthLines() } label: {
            Image(systemName: "line.3.horizontal").rotationEffect(.degrees(90))
        }
        .buttonStyle(ToolButtonStyle(isActive: on))
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .accessibilityLabel(on ? "Hide north lines" : "Show north lines")
        .accessibilityIdentifier("northLinesToggle")
        .help(on ? "Hide north lines (⇧⌘G)" : "Show north lines (⇧⌘G) · settings in the Map tab")
    }
}

/// View the whole map (frame + all objects), like "Zoom to fit" in OCAD.
private struct FitMapButton: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        Button { model.mapCommand = MapCommand(kind: .fitMap) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
            .buttonStyle(ToolButtonStyle())
            .keyboardShortcut("0", modifiers: .command)
            .accessibilityLabel("View whole map")
            .help("View whole map (⌘0)")
    }
}

/// Show/hide the GPS position (radar + view direction). Hold = center the map on my location.
private struct LocationButton: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var live: LiveMapState
    /// Inside the tool rail: no panel of its own (highlighted blue only when active), rail button size.
    var embedded = false

    var body: some View {
        let on = model.showsMyLocation
        let radius = embedded ? CP.Radius.control : CP.Radius.panel
        VStack(spacing: 2) {
            Image(systemName: model.showsMyLocation ? "location.fill" : "location")
                .font(.system(size: CP.fs(18)))
                .foregroundStyle(model.showsMyLocation ? CP.sky.strong : CP.ink)
                .overlay(alignment: .bottomTrailing) {
                    if !LicenseManager.shared.isPro {
                        Image(systemName: "lock.fill").font(.system(size: CP.fs(8), weight: .bold))
                            .foregroundStyle(CP.peach.strong).offset(x: 5, y: 3)
                    }
                }
            if model.showsMyLocation {
                Text(live.myAccuracyM.map { $0 < 10 ? String(format: "±%.1f m", $0) : String(format: "±%.0f m", $0) } ?? "searching…")
                    .font(CP.mono(10, weight: .medium))
                    .foregroundStyle(accuracyColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: embedded ? CP.hitTarget : MapControls.width, height: on ? 52 : CP.hitTarget)
        .background(on ? CP.sky.fill : (embedded ? .clear : CP.paper), in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(on ? CP.sky.strong : (embedded ? .clear : CP.line)))
        .shadow(color: .black.opacity(embedded ? 0 : 0.08), radius: 1, y: 1)
        .contentShape(Rectangle())
        // Starter: my location needs a license key.
        .onTapGesture {
            if model.showsMyLocation { model.showsMyLocation = false }
            else if LicenseManager.shared.require(.myLocation) { model.showsMyLocation = true }
        }
        .onLongPressGesture {
            if LicenseManager.shared.require(.myLocation) { model.mapCommand = MapCommand(kind: .followUser) }
        }
        .accessibilityElement()
        .accessibilityLabel(model.showsMyLocation ? "Hide my location" : "Show my location")
        .help(model.showsMyLocation ? "Hide my location · hold = center map" : "Show my location · hold = center map")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Center on my location") {
            if LicenseManager.shared.require(.myLocation) { model.mapCommand = MapCommand(kind: .followUser) }
        }
    }

    /// Green ≤ 5 m, yellow ≤ 15 m, red above that (an iPad under canopy is usually 5–15 m).
    private var accuracyColor: Color {
        guard let a = live.myAccuracyM else { return CP.inkMuted }
        return a <= 5 ? CP.sage.strong : (a <= 15 ? CP.butter.strong : CP.rose.strong)
    }
}

/// The needle points north on screen (follows map rotation). Number = iPad heading when a magnetometer is available,
/// otherwise the map heading. Tap: back to north-up; if already north-up, the map follows the iPad heading.
struct DigitalCompass: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var live: LiveMapState
    /// Inside the tool rail: no panel of its own (highlighted blue only while following the iPad heading).
    var embedded = false

    private var isRotated: Bool {
        let h = live.mapHeading.truncatingRemainder(dividingBy: 360)
        return min(abs(h), abs(360 - abs(h))) > 0.5
    }

    private var readout: Double { live.deviceHeading ?? live.mapHeading }

    var body: some View {
        // Mac: no iPad heading to follow, so the compass only shows while the map is rotated (tap = north up).
        if !CP.isMac || isRotated { compass }
    }

    private var compass: some View {
        Button(action: tap) {
            VStack(spacing: 2) {
                dial
                readoutText
            }
            .padding(.vertical, CP.Space.xs)
            .frame(width: embedded ? CP.hitTarget : MapControls.width)
            .background(model.followsHeading ? CP.sky.fill : (embedded ? .clear : CP.paper),
                        in: RoundedRectangle(cornerRadius: embedded ? CP.Radius.control : CP.Radius.panel))
            .overlay(RoundedRectangle(cornerRadius: embedded ? CP.Radius.control : CP.Radius.panel)
                .strokeBorder(model.followsHeading ? CP.sky.strong : (embedded ? .clear : CP.line)))
            .shadow(color: .black.opacity(embedded ? 0 : 0.08), radius: 1, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compass, heading \(Int(readout.rounded())) degrees")
        .help(isRotated ? "Compass: tap = back to north up" : "Compass: tap = map follows iPad heading")
        .accessibilityHint(isRotated ? "Tap to return to north up" : "Tap to make the map follow the iPad heading")
    }

    private var dial: some View {
        ZStack {
            Circle().strokeBorder(CP.line, lineWidth: 1)
            ForEach(0..<12) { i in
                Rectangle()
                    .fill(CP.inkMuted)
                    .frame(width: 1, height: i % 3 == 0 ? 5 : 3)
                    .offset(y: -19)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            Needle()
                .rotationEffect(.degrees(-live.mapHeading))
        }
        .frame(width: 44, height: 44)
    }

    private var readoutText: some View {
        Text(String(format: "%03.0f° %@", readout.rounded().truncatingRemainder(dividingBy: 360), Self.cardinal(readout)))
            .font(CP.mono(11, weight: .medium))
            .foregroundStyle(model.followsHeading ? CP.sky.strong : CP.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func tap() {
        if model.followsHeading || isRotated {
            model.followsHeading = false
            model.mapCommand = MapCommand(kind: .northUp)
        } else if live.deviceHeading != nil {
            model.followsHeading = true
            model.mapCommand = MapCommand(kind: .followHeading)
        } else {
            model.notice = "The iPad compass isn't available on this device. Rotate the map with two fingers."
        }
    }

    /// Short compass point names in English.
    static func cardinal(_ deg: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return names[i]
    }
}

private struct Needle: View {
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 0, y: -14)); p.addLine(to: CGPoint(x: 4, y: 0)); p.addLine(to: CGPoint(x: -4, y: 0)); p.closeSubpath()
            }
            .fill(CP.rose.strong)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 14)); p.addLine(to: CGPoint(x: 4, y: 0)); p.addLine(to: CGPoint(x: -4, y: 0)); p.closeSubpath()
            }
            .fill(CP.inkMuted)
        }
        .offset(x: 22, y: 22)
        .frame(width: 44, height: 44)
    }
}

// MARK: - Tool rail

private struct ToolRail: View {
    @ObservedObject var model: WorkspaceModel
    /// Map controls in a second column (still one panel) when one column doesn't fit the screen height.
    var twoColumns = false
    /// Mac: one horizontal row at the top (groups separated by vertical lines).
    var horizontal = false
    /// Mac: the compass moves to the right corner of the toolbar band.
    var showsCompass = true
    /// Horizontal band on a narrow screen (iPad portrait): drawing tools and map controls on separate rows.
    var part: Part = .all

    enum Part { case all, tools, mapControls }

    /// Groups: navigate/move/node/measure · pencil sketch · vector.
    private let groups: [[Tool]] = [[.navigate, .select, .node, .measure], [.pen, .eraser], [.point, .bezier, .freehand, .rectangle, .ellipse]]

    var body: some View {
        Group {
            if horizontal {
                HStack(spacing: CP.Space.xs) {
                    if part != .mapControls { tools }
                    if part == .all { divider }
                    if part != .tools { mapControls }
                }
                .fixedSize()
            } else if twoColumns {
                HStack(alignment: .top, spacing: CP.Space.xs) {
                    VStack(spacing: CP.Space.xs) { tools }
                    Rectangle().fill(CP.line).frame(width: 1).padding(.vertical, CP.Space.xs)
                    VStack(spacing: CP.Space.xs) { mapControls }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: CP.Space.xs) {
                    tools
                    divider
                    mapControls
                }
            }
        }
        .modifier(DockChrome())
    }

    @ViewBuilder
    private var tools: some View {
        ForEach(Array(groups.enumerated()), id: \.offset) { i, group in
            if i > 0 { divider }
            ForEach(group) { tool in
                Button { model.tool = tool } label: { Image(systemName: tool.symbol) }
                    .buttonStyle(ToolButtonStyle(isActive: model.tool == tool))
                    .keyboardShortcut(KeyEquivalent(tool.shortcut), modifiers: [])
                    .accessibilityLabel(tool.label)
                    .help("\(tool.label)\(tool.hint.map { ": \($0)" } ?? "") (\(String(tool.shortcut).uppercased()))")
            }
        }
    }

    /// Map controls (formerly a separate panel below the rail): zoom, whole map, frame, compass, location.
    @ViewBuilder
    private var mapControls: some View {
        Button { model.mapCommand = MapCommand(kind: .zoom(2)) } label: { Image(systemName: "plus.magnifyingglass") }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel("Zoom in")
            .help("Zoom in (⌘=)")
        Button { model.mapCommand = MapCommand(kind: .zoom(0.5)) } label: { Image(systemName: "minus.magnifyingglass") }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel("Zoom out")
            .help("Zoom out (⌘−)")
        FitMapButton(model: model)
        Button { model.mapCommand = MapCommand(kind: .zoomToFrame) } label: { Image(systemName: "rectangle.dashed") }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel("Zoom to frame")
            .help("Zoom to map frame")
        NorthLinesButton(model: model)
        divider
        if showsCompass { DigitalCompass(model: model, live: model.live, embedded: true) }
        LocationButton(model: model, live: model.live, embedded: true)
    }

    private var divider: some View {
        Rectangle().fill(CP.line)
            .frame(width: horizontal ? 1 : 28, height: horizontal ? 28 : 1)
            .padding(horizontal ? .horizontal : .vertical, CP.Space.xs)
    }
}

// MARK: - Vector toolbar

/// Contextual bar above the dock: hints + actions for the pen tool, rectangle/ellipse, or the selected object.
private struct VectorToolBar: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.docked) private var docked

    var body: some View {
        Group {
            if model.cutMode, let f = model.selectedFeature {
                cutBar(f)
            } else {
                toolBar
            }
        }
        .labelStyle(.titleAndIcon)
    }

    /// Cut / Split area prompt. Areas: tool buttons to cut with two points, a rectangle, an ellipse, or a path.
    @ViewBuilder
    private func cutBar(_ f: Feature) -> some View {
        bar {
            Image(systemName: "scissors").foregroundStyle(CP.ink)
            Text(cutPrompt(f))
                .font(.system(size: CP.fs(13))).foregroundStyle(CP.ink)
                .accessibilityIdentifier("cutPrompt")
            if f.kind == .area {
                ButtonGroup {
                    cutToolButton(nil, "Two points", icon: "line.diagonal",
                                  help: "Split with a straight line: tap two points on the area's edge")
                    GroupDivider()
                    cutToolButton(.rectangle, "Cut with rectangle", icon: Tool.rectangle.symbol,
                                  help: "Cut with a rectangle: drag over the area to cut that part away; inside the area it makes a hole (M)")
                    cutToolButton(.ellipse, "Cut with ellipse", icon: Tool.ellipse.symbol,
                                  help: "Cut with an ellipse: drag over the area to cut that part away; inside the area it makes a hole (L)")
                    cutToolButton(.bezier, "Cut along pen path", icon: Tool.bezier.symbol,
                                  help: "Split along a pen path drawn across the area; close the path to cut its shape away (P)")
                    cutToolButton(.freehand, "Cut along freehand line", icon: Tool.freehand.symbol,
                                  help: "Split along a freehand line drawn across the area (F)")
                }
            }
            if model.tool == .bezier, !model.draftNodes.isEmpty {
                Button { model.finishDraft(as: .line) } label: { Label("Split along path", systemImage: "checkmark") }
                    .help("Split along the path (Return)")
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(model.draftNodes.count < 2)
                Button { model.removeLastDraftNode() } label: { Label("Delete last point", systemImage: "delete.left") }
                    .help("Delete last point (Delete)")
                    .keyboardShortcut(.delete, modifiers: [])
            }
            Button(role: .cancel) { model.cancelCut() } label: { Label("Cancel", systemImage: "xmark") }
                .buttonStyle(PastelButtonStyle(tone: CP.rose))
                .help("Cancel (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("cutCancel")
        }
    }

    private func cutPrompt(_ f: Feature) -> String {
        if f.kind == .line { return "Cut: tap a point on the line to cut it in two, or drag a box to cut out a part" }
        switch model.tool {
        case .rectangle: return "Cut area: drag a rectangle over the area to cut that part away (inside = a hole)"
        case .ellipse: return "Cut area: drag an ellipse over the area to cut that part away (inside = a hole)"
        case .bezier: return "Cut area: draw a path across the area, double-tap to split; close it to cut its shape away"
        case .freehand: return "Cut area: draw a line across the area to split it"
        default:
            return model.cutStart == nil ? "Split area: tap two points on the edge, or draw a rectangle, ellipse or path across it"
                : "Split area: tap the second point on the opposite edge"
        }
    }

    /// One cut tool in the Split area prompt; nil = two points on the edge (Move/Node Tool).
    private func cutToolButton(_ tool: Tool?, _ title: String, icon: String, help: String) -> some View {
        let active = tool.map { model.tool == $0 } ?? model.tool.selects
        return Button {
            model.tool = tool ?? model.cutReturnTool ?? (model.tool.selects ? model.tool : .select)
        } label: { Label(title, systemImage: icon) }
            .buttonStyle(GroupedButtonStyle(isActive: active))
            .help(help)
            .accessibilityLabel(title)
            .accessibilityIdentifier("cutTool-\(tool?.rawValue ?? "points")")
    }

    @ViewBuilder
    private var toolBar: some View {
            switch model.tool {
            case .bezier:
                if model.draftNodes.isEmpty {
                    // Tap = corner point · drag = curve · double tap = done · tap two points on the same
                    // object = its shape is followed · an end snapped to an object with the same symbol = merged.
                    EmptyView()
                } else {
                    bar {
                        Text(verbatim: "\(model.draftNodes.count) points").font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                        Button { model.finishDraftForActiveSymbol() } label: {
                            Label(model.activeSymbol?.kind == .area ? "Finish area" : "Finish line", systemImage: "checkmark")
                        }
                            .help(model.activeSymbol?.kind == .area ? "Finish area (Return)" : "Finish line (Return)")
                            .keyboardShortcut(.return, modifiers: [])
                        Button { model.finishDraft(as: .area) } label: { Label("Close as area", systemImage: "square.dashed") }
                            .help("Close as area")
                            .disabled(model.draftNodes.count < 3)
                        Button { model.removeLastDraftNode() } label: { Label("Delete last point", systemImage: "delete.left") }
                            .help("Delete last point (Delete)")
                            .keyboardShortcut(.delete, modifiers: [])
                        Button(role: .destructive) { model.cancelDraft() } label: { Label("Cancel", systemImage: "xmark") }
                            .help("Cancel (Esc)")
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                }
            case .point:
                if let s = model.activeSymbol, s.kind == .point {
                    EmptyView()   // tap the map to place (snaps to lines/corners of other objects)
                } else {
                    hint("Point symbol: select a point symbol in the Symbol panel (e.g. 204.0 Boulder, 417.0 tree), then tap the map.")
                }
            case .freehand, .rectangle, .ellipse:
                // Freehand: the stroke is smoothed; parts running along other objects follow their shape.
                // Rectangle/ellipse: drag from corner to corner (corners snap to other objects).
                EmptyView()
            case .measure:
                if let m = model.measurement {
                    bar {
                        Image(systemName: "ruler").foregroundStyle(CP.ink)
                        Text(verbatim: Fmt.meters(m.meters, decimals: m.meters < 100 ? 1 : 0))
                            .font(CP.mono(15, weight: .semibold)).foregroundStyle(CP.ink)
                            .accessibilityIdentifier("measureDistance")
                        Text(verbatim: "\(Fmt.mm(m.paperMM(scaleDenominator: model.project.sheet.scaleDenominator), decimals: 1)) on the 1:\(model.project.sheet.scaleDenominator) map")
                            .font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                        Text(verbatim: "Azimuth \(Int(m.gridBearing.rounded()) % 360)°")
                            .font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                            .help("Grid azimuth (from UTM grid north)")
                        Button { model.measurement = nil } label: { Label("Clear measurement", systemImage: "xmark") }
                            .help("Clear measurement (Esc)")
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                } else {
                    hint("Measure: drag from the start point to the end point. The ends snap to objects.")
                }
            case .select, .node:
                if model.isMultiSelection {
                    bar {
                        Text(verbatim: "\(model.selectedIDs.count) objects selected")
                            .font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                            .accessibilityIdentifier("selectionCount")
                        let mergeKinds = model.selectionMergeKinds
                        if !mergeKinds.isEmpty {
                            // Lines = Join (connect at the ends), areas = Merge (unify shapes).
                            MergeButton(title: mergeKinds == [.line] ? "Join" : (mergeKinds == [.area] ? "Merge" : "Join & Merge"),
                                        help: mergeKinds == [.line] ? "Join selected lines with the same symbol whose ends meet"
                                            : mergeKinds == [.area] ? "Merge selected touching areas with the same symbol"
                                            : "Join lines and merge areas with the same symbol that meet") { model.mergeSelection() }
                                .accessibilityIdentifier("mergeSelection")
                        }
                        MultiSymbolSwitchButton(model: model)
                            .disabled(model.editableSelection.isEmpty)
                        Button { model.duplicateSelection() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            .help("Duplicate (⌘D)")
                            .keyboardShortcut("d", modifiers: .command)
                        Button(role: .destructive) { model.deleteSelection() } label: { Label("Delete \(model.selectedIDs.count) objects", systemImage: "trash") }
                            .buttonStyle(PastelButtonStyle(tone: CP.rose))
                            .help("Delete \(model.selectedIDs.count) objects (Delete)")
                            .keyboardShortcut(.delete, modifiers: [])
                        Button { model.deselect() } label: { Label("Done", systemImage: "checkmark") }
                            .buttonStyle(PastelButtonStyle(tone: CP.sage))
                            .help("Done (Esc)")
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                } else if let f = model.selectedFeature {
                    bar {
                        BarTitle(text: f.displayName)
                        if model.mergeCandidateCount > 0 {
                            // OCAD Merge / OOM Connect paths + Unify areas: objects with the same symbol that meet.
                            // In front and prominent so it is noticed as soon as two objects meet.
                            MergeButton(title: f.kind == .line ? "Join" : "Merge",
                                        help: f.kind == .line ? "Join with a line with the same symbol whose end meets"
                                                              : "Merge with a touching area with the same symbol") { model.mergeSelected() }
                                .accessibilityIdentifier("mergeSelected")
                        }
                        if f.kind != .point {
                            Segmented("Kind", selection: Binding(get: { f.kind }, set: { k in model.updateFeature(f.id) { $0.kind = k } }),
                                      [FeatureKind.line, .area].map { .init($0, $0.label) })
                            .frame(width: 140)
                            .disabled(f.isLocked || (f.nodes.count < 3))
                        }
                        // Size group: − value + (points in % of standard size, lines/areas in mm), then back to standard.
                        ButtonGroup {
                            Button { f.kind == .point ? model.resizeSelected(by: 1 / 1.1) : model.adjustSelectedWidth(by: -0.01) } label: {
                                Label(f.kind == .point ? "Smaller" : "Thinner", systemImage: "minus")
                            }
                            .help(f.kind == .point ? "Make symbol smaller" : "Make line thinner (−0.01 mm)")
                            Text(verbatim: f.kind == .point ? "\(Int((f.effectiveSizeFactor * 100).rounded()))%" : Fmt.mm(f.widthMM))
                                .font(CP.mono(12, weight: .medium))
                                .foregroundStyle(CP.sand.strong)
                                .frame(minWidth: 52)
                            Button { f.kind == .point ? model.resizeSelected(by: 1.1) : model.adjustSelectedWidth(by: 0.01) } label: {
                                Label(f.kind == .point ? "Larger" : "Thicker", systemImage: "plus")
                            }
                            .help(f.kind == .point ? "Make symbol larger" : "Make line thicker (+0.01 mm)")
                            if (f.kind == .point && f.sizeFactor != nil)
                                || (f.kind != .point && f.standardWidthMM.map { abs($0 - f.widthMM) > 0.005 } == true) {
                                GroupDivider()
                                Button { model.resetSelectedSize() } label: { Label("Standard", systemImage: "arrow.counterclockwise") }
                                    .help("Back to IOF standard size")
                            }
                        }
                        .buttonStyle(GroupedButtonStyle())
                        .disabled(f.isLocked)
                        // Symbol group: change symbol, guide, fill, switch to the panel's symbol, pen color.
                        ButtonGroup {
                            SymbolSwitchButton(model: model, feature: f)
                                .disabled(f.isLocked)
                            if let code = f.symbolCode {
                                GroupDivider()
                                SymbolGuideButton(isOpen: model.symbolGuide?.code == code, inGroup: true) {
                                    model.symbolGuideSearching = false
                                    model.openSymbolGuide(code, name: f.symbolName ?? "")
                                }
                                .accessibilityIdentifier("guideSelectedObject")
                            }
                            if f.canFillWithArea {
                                // OCAD Fill: fill the line's shape with an area symbol; the line is kept.
                                GroupDivider()
                                FillAreaButton(model: model)
                                    .disabled(f.isLocked)
                            }
                            if let s = model.activeSymbol, s.code != f.symbolCode, model.canSwitch(f, to: s) {
                                // OOM "Switch symbol": select an object, pick a symbol in the panel, then switch.
                                GroupDivider()
                                Button { model.switchSelectedSymbol() } label: {
                                    Label("Change symbol → \(s.code)", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .help("Change object symbol to \(s.code) \(s.name)")
                                .disabled(f.isLocked)
                            }
                            if f.symbolCode == nil {
                                GroupDivider()
                                Button { model.applyPenStyleToSelection() } label: { Label("Use pen color", systemImage: "paintbrush") }
                                    .help("Use pen color")
                                    .disabled(f.isLocked)
                            }
                        }
                        .buttonStyle(GroupedButtonStyle())
                        if model.tool == .node, let i = model.selectedNodeIndex, f.allNodes.indices.contains(i) {
                            let count = model.selectedNodeIndices.count
                            NodeStylePicker(model: model, current: f.nodeStyle(at: i))
                                .disabled(f.isLocked)
                            // With points selected, the Delete key removes the points (like Illustrator), not the object.
                            Button { model.deleteSelectedNode() } label: {
                                Label(count > 1 ? "Delete \(count) points" : "Delete point", systemImage: "minus.circle")
                            }
                            .help(count > 1 ? "Delete \(count) points (Delete)" : "Delete point (Delete)")
                            .keyboardShortcut(.delete, modifiers: [])
                            .disabled(f.isLocked)
                            if model.selectedHoleIndex != nil {
                                // A point of a hole is active: remove the whole hole (the area is filled there again).
                                Button { model.removeSelectedHole() } label: { Label("Remove hole", systemImage: "circle.dashed") }
                                    .help("Remove this hole: fill the area there again")
                                    .accessibilityIdentifier("removeHole")
                                    .disabled(f.isLocked)
                            }
                        }
                        // Shape group: rotate, cut/split, scale, parallel, reverse.
                        ButtonGroup {
                            RotationButton(model: model, feature: f)
                                .disabled(f.isLocked)
                            if f.kind != .point {
                                GroupDivider()
                                ShapeEditButtons(model: model, feature: f)
                                    .disabled(f.isLocked)
                            }
                        }
                        .buttonStyle(GroupedButtonStyle())
                        // Object group: duplicate, delete.
                        let pointsSelected = model.tool == .node && model.selectedNodeIndex.map { f.allNodes.indices.contains($0) } == true
                        ButtonGroup {
                            Button { model.duplicateSelection() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                .help("Duplicate (⌘D)")
                                .keyboardShortcut("d", modifiers: .command)
                            GroupDivider()
                            Button(role: .destructive) { model.deleteSelection() } label: { Label("Delete object", systemImage: "trash") }
                                .buttonStyle(GroupedButtonStyle(tint: CP.rose.strong))
                                .help(pointsSelected ? "Delete object" : "Delete object (Delete)")
                                .keyboardShortcut(pointsSelected ? nil : KeyboardShortcut(.delete, modifiers: []))
                        }
                        .buttonStyle(GroupedButtonStyle())
                        Button { model.deselect() } label: { Label("Done", systemImage: "checkmark") }
                            .buttonStyle(PastelButtonStyle(tone: CP.sage))
                            .help("Done (Esc)")
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                } else {
                    // Tap an object = select · drag on empty space = selection box · Shift + tap = add · ⌘A = all.
                    EmptyView()
                }
            default:
                EmptyView()
            }
    }

    @ViewBuilder
    private func hint(_ text: String) -> some View {
        if docked {
            Text(text)
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .padding(.horizontal, CP.Space.s)
                .padding(.vertical, CP.Space.xs + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(CP.line).frame(height: 1) }
        } else {
            Text(text)
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .padding(.horizontal, CP.Space.m)
                .padding(.vertical, CP.Space.s)
                .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
        }
    }

    /// Icons only (names in the tooltip on Mac and in the accessibility label); narrower still on small screens.
    private func bar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let items = content()
        let panel = { (content: AnyView) in
            content
                .font(.system(size: CP.fs(13), weight: .medium))
                .buttonStyle(PastelButtonStyle(tone: CP.sand))
                .modifier(BarChrome())
        }
        // Full labels → icons only → icons without the object name → finally horizontally scrollable, so the bar
        // never pushes the screen out.
        return ViewThatFits(in: .horizontal) {
            panel(AnyView(HStack(spacing: CP.Space.s) { items }.labelStyle(.iconOnly).lineLimit(1).fixedSize()))
            // Narrow (iPad portrait): no object name, and the shape tools fold into one menu.
            panel(AnyView(HStack(spacing: CP.Space.xs) { items }.labelStyle(.iconOnly).lineLimit(1).fixedSize()
                .environment(\.barCompact, true)))
            ScrollView(.horizontal, showsIndicators: false) {
                panel(AnyView(HStack(spacing: CP.Space.s) { items }.labelStyle(.iconOnly).lineLimit(1).fixedSize()))
                    .padding(.horizontal, CP.Space.m)
            }
        }
    }
}

/// Toolbar: floating panel (iPad) or a left-aligned row in the top toolbar band (Mac).
private struct BarChrome: ViewModifier {
    @Environment(\.docked) private var docked

    func body(content: Content) -> some View {
        if docked {
            content
                .padding(.horizontal, CP.Space.s)
                .padding(.vertical, CP.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(CP.line).frame(height: 1) }
        } else {
            content
                .padding(.horizontal, CP.Space.m)
                .padding(.vertical, CP.Space.s)
                .cpPanel()
        }
    }
}

/// Object name in the toolbar; hidden in the most compact bar variant (the name also shows in the layers panel).
private struct BarTitle: View {
    let text: String
    @Environment(\.barCompact) private var compact

    var body: some View {
        if !compact {
            Text(text).font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink).lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .leading)
        }
    }
}

private struct BarCompactKey: EnvironmentKey { static let defaultValue = false }
private struct DockedKey: EnvironmentKey { static let defaultValue = false }

/// Mac: the rail, pen dock, and toolbar are attached to the top toolbar band (no floating panel frame).
struct DockChrome: ViewModifier {
    @Environment(\.docked) private var docked
    var padding: CGFloat = CP.Space.xs
    var horizontalPadding: CGFloat?

    func body(content: Content) -> some View {
        if docked {
            content
        } else {
            content
                .padding(.vertical, padding)
                .padding(.horizontal, horizontalPadding ?? padding)
                .cpPanel()
        }
    }
}

/// Mac toolbar band: paper background, bottom line, content aligned left.
struct MacBand: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.docked, true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CP.paper)
            .overlay(alignment: .bottom) { Rectangle().fill(CP.line).frame(height: 1) }
    }
}

/// Bottom edge of the toolbar band (in coordinate space `space`), used to shift the map canvas below it.
struct BandBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct BandBottomReader: ViewModifier {
    let space: String

    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear.preference(key: BandBottomKey.self, value: g.frame(in: .named(space)).maxY)
        })
    }
}

/// Right panel: floating (iPad) or attached full height on the right side of the window with a left border (Mac).
struct SidePanelChrome: ViewModifier {
    var maxHeight: CGFloat = .infinity
    var minHeight: CGFloat = 0

    /// Attached full height on the right, below the toolbar band (Mac and iPad).
    func body(content: Content) -> some View {
        content
            .frame(maxHeight: .infinity)
            .background(CP.paper)
            .overlay(alignment: .leading) { Rectangle().fill(CP.line).frame(width: 1) }
    }
}

/// Spacing for the element in the right corner of the toolbar band (compass), so it isn't flush with the window edge.
struct BandCornerPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.leading, CP.Space.s)
            .padding(.trailing, CP.Space.m)
            .padding(.vertical, CP.Space.xs)
    }
}

/// Vertical separator line between groups in the toolbar band.
struct BandSeparator: View {
    var body: some View { Rectangle().fill(CP.line).frame(width: 1, height: 28) }
}

extension EnvironmentValues {
    /// Toolbar in its most compact variant (narrow screen).
    var barCompact: Bool {
        get { self[BarCompactKey.self] }
        set { self[BarCompactKey.self] = newValue }
    }

    /// Attached to the top toolbar band (Mac).
    var docked: Bool {
        get { self[DockedKey.self] }
        set { self[DockedKey.self] = newValue }
    }
}



// MARK: - Pen dock

private struct PenDockChrome: ViewModifier {
    @Environment(\.docked) private var docked

    func body(content: Content) -> some View {
        if docked {
            content
        } else {
            content
                .padding(.horizontal, CP.Space.m)
                .padding(.vertical, CP.Space.xs)
                .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
                .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(CP.peach.fill, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
    }
}

private struct PenDock: View {
    @ObservedObject var model: WorkspaceModel
    /// The six sketch pen colors can be shown or hidden (saved per device); hidden by default so the dock stays compact.
    @AppStorage("showPenColors") private var showPenColors = false

    var body: some View {
        HStack(spacing: CP.Space.m) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { showPenColors.toggle() }
            } label: {
                Image(systemName: showPenColors ? "paintpalette.fill" : "paintpalette")
                    .font(.system(size: CP.fs(17)))
                    .foregroundStyle(showPenColors ? CP.peach.strong : CP.inkMuted)
                    .frame(width: CP.hitTarget, height: CP.hitTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("togglePenColors")
            .accessibilityLabel(showPenColors ? "Hide pen colors" : "Show pen colors")
            .help(showPenColors ? "Hide pen colors" : "Show pen colors")

            if showPenColors {
                penColors
            }

            Rectangle().fill(CP.line).frame(width: 1, height: 28)

            if let s = model.activeSymbol {
                SymbolSizeControl(model: model, symbol: s)
            } else {
                penWidthControls
            }

            // Finger drawing is an iPad thing (no Pencil); on Mac the mouse / trackpad always draws.
            if !CP.isMac {
                Rectangle().fill(CP.line).frame(width: 1, height: 28)

                Toggle(isOn: $model.fingerDraws) {
                    Image(systemName: "hand.point.up.left")
                }
                .toggleStyle(.button)
                .tint(CP.peach.strong)
                .accessibilityLabel("Draw with finger")
                .help("For iPad without Pencil or the simulator: one finger draws, two fingers navigate")
            }
        }
        .modifier(PenDockChrome())
    }

    /// Sketch pen presets (black, brown, blue, yellow, green, red).
    @ViewBuilder
    private var penColors: some View {
            ForEach(PenPreset.isom) { preset in
                let active = model.pen.colorHex == preset.colorHex
                Button {
                    model.pen = preset
                    model.clearSymbol()
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
                .accessibilityLabel("Pen \(preset.name) \(Fmt.mm(preset.widthMM))")
                .help("Pen \(preset.name) \(Fmt.mm(preset.widthMM))")
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
    }

    @ViewBuilder
    private var penWidthControls: some View {
            Button { model.setPenWidth(model.pen.widthMM - 0.01) } label: { Image(systemName: "minus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("[", modifiers: [])
                .accessibilityLabel("Decrease width")
                .help("Decrease width ([)")
            Slider(value: Binding(get: { model.pen.widthMM }, set: { model.setPenWidth($0) }),
                   in: PenPreset.widthRange)
                .frame(width: 140)
                .accessibilityLabel("Line width")
                .help("Line width")
            Button { model.setPenWidth(model.pen.widthMM + 0.01) } label: { Image(systemName: "plus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("]", modifiers: [])
                .accessibilityLabel("Increase width")
                .help("Increase width (])")
            Text(Fmt.mm(model.pen.widthMM))
                .font(CP.mono(15, weight: .medium))
                .foregroundStyle(CP.ink)
                .frame(width: 76, alignment: .trailing)
    }
}

/// Active symbol in the dock: shape preview, code, and size (% of the symbol set's IOF standard) with a Standard button.
private struct SymbolSizeControl: View {
    @ObservedObject var model: WorkspaceModel
    let symbol: MapSymbol

    private var isPoint: Bool { symbol.kind == .point }
    private var standard: Double { model.activeStandardWidthMM ?? symbol.drawingWidthMM }
    private var isStandard: Bool {
        isPoint ? model.symbolSizeFactor == 1 : abs(model.pen.widthMM - standard) < 0.005
    }

    var body: some View {
        HStack(spacing: CP.Space.s) {
            SymbolSwatch(symbol: symbol)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: symbol.code).font(CP.mono(12, weight: .semibold)).foregroundStyle(CP.ink)
                Text(symbol.name).font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted).lineLimit(1)
            }
            .frame(width: 104, alignment: .leading)
            Button { step(-1) } label: { Image(systemName: "minus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("[", modifiers: [])
                .accessibilityLabel(isPoint ? "Make symbol smaller" : "Make line 0.01 mm thinner")
                .help(isPoint ? "Make symbol smaller ([)" : "Make line 0.01 mm thinner ([)")
            readout
                .frame(width: 84)
            Button { step(1) } label: { Image(systemName: "plus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("]", modifiers: [])
                .accessibilityLabel(isPoint ? "Make symbol larger" : "Make line 0.01 mm thicker")
                .help(isPoint ? "Make symbol larger (])" : "Make line 0.01 mm thicker (])")
            Button { reset() } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(ToolButtonStyle())
                .disabled(isStandard)
                .accessibilityLabel("Standard size")
                .help("Back to the symbol set's IOF standard size")
            SymbolGuideButton(isOpen: model.symbolGuide?.code == symbol.code) {
                if model.symbolGuide?.code == symbol.code { model.closeSymbolGuide() } else { model.symbolGuideSearching = false; model.openSymbolGuide(symbol.code, name: symbol.name) }
            }
            .accessibilityIdentifier("guideActiveSymbol")
        }
    }

    /// Point: percent (Ø mm below it). Line/area: width in mm (IOF standard percent below it), tap = presets.
    @ViewBuilder
    private var readout: some View {
        if isPoint {
            VStack(spacing: 0) {
                Text(verbatim: "\(Int((model.symbolSizeFactor * 100).rounded()))%")
                    .font(CP.mono(15, weight: .medium))
                    .foregroundStyle(isStandard ? CP.ink : CP.peach.strong)
                Text(verbatim: "Ø \(Fmt.mm((symbol.pointElements ?? []).diameterMM * model.symbolSizeFactor))")
                    .font(CP.mono(10)).foregroundStyle(CP.inkMuted)
            }
        } else {
            SolidMenu(items: [0.5, 0.75, 1, 1.25, 1.5, 2].map { k in
                .action("\(Int(k * 100))% · \(Fmt.mm(PenPreset.clampWidth(standard * k)))",
                        checked: abs(model.pen.widthMM - PenPreset.clampWidth(standard * k)) < 0.001,
                        section: "Width from IOF standard \(Fmt.mm(standard))") { model.setSymbolLineWidth(standard * k) }
            }, width: 240) {
                VStack(spacing: 0) {
                    Text(Fmt.mm(model.pen.widthMM))
                        .font(CP.mono(14, weight: .medium))
                        .foregroundStyle(isStandard ? CP.ink : CP.peach.strong)
                    Text(verbatim: "\(Int((model.pen.widthMM / max(standard, 0.01) * 100).rounded()))% IOF")
                        .font(CP.mono(10)).foregroundStyle(CP.inkMuted)
                }
            }
            .accessibilityLabel("Line width \(Fmt.mm(model.pen.widthMM))")
        }
    }

    private func step(_ dir: Double) {
        if isPoint {
            model.setSymbolSize(dir > 0 ? model.symbolSizeFactor * 1.1 : model.symbolSizeFactor / 1.1)
        } else {
            model.setSymbolLineWidth(model.pen.widthMM + 0.01 * dir)
        }
    }

    private func reset() {
        if isPoint { model.setSymbolSize(1) } else { model.setSymbolLineWidth(standard) }
    }
}

// MARK: - Object rotation

/// "↻ angle" button in the selected-object bar; opens a panel with a 0–360° slider, ±1°/±15° steps, and presets.
private struct RotationButton: View {
    @ObservedObject var model: WorkspaceModel
    let feature: Feature
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Label("Rotate \(degreesText(feature.rotationDegrees))", systemImage: "rotate.right")
        }
        .popover(isPresented: $showing) {
            RotationPanel(model: model)
                .frame(width: 320)
                .padding(CP.Space.l)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(CP.paper)
        }
        .accessibilityLabel("Rotate object, \(Int(feature.rotationDegrees.rounded())) degrees")
        .help("Rotate object (\(Int(feature.rotationDegrees.rounded()))°)")
    }
}

private struct RotationPanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var before: [Feature]?
    @State private var liveDegrees: Double?

    private var current: Double { liveDegrees ?? model.selectedFeature?.rotationDegrees ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack {
                Text("Rotate object").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                Spacer()
                Text(verbatim: degreesText(current)).font(CP.mono(17, weight: .semibold)).foregroundStyle(CP.ink)
            }
            Text("Clockwise from grid north, rotating around the object's center.")
                .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            Slider(value: Binding(get: { current }, set: { v in
                liveDegrees = v
                model.rotateSelectedLive(to: v)
            }), in: 0...360, step: 1) { editing in
                if editing {
                    before = model.features
                } else {
                    if let before { model.commitFeatureEdit(from: before) }
                    before = nil
                    liveDegrees = nil
                }
            }
            .accessibilityLabel("Rotation angle")
            .help("Rotation angle")
            .accessibilityValue("\(Int(current.rounded())) degrees")
            HStack(spacing: CP.Space.s) {
                ForEach([-15.0, -1, 1, 15], id: \.self) { d in
                    Button(d > 0 ? "+\(Int(d))°" : "\(Int(d))°") { model.setSelectedRotation(current + d) }
                        .font(CP.mono(13, weight: .medium))
                        .buttonStyle(PastelButtonStyle(tone: CP.sand))
                }
            }
            HStack(spacing: CP.Space.xs) {
                ForEach([0.0, 45, 90, 135, 180, 270], id: \.self) { d in
                    Button(degreesText(d)) { model.setSelectedRotation(d) }
                        .font(CP.mono(12))
                        .buttonStyle(PastelButtonStyle(tone: abs(current - d) < 0.05 ? CP.sage : CP.sand))
                }
            }
        }
    }
}

// MARK: - Edit shape (OCAD: Cut, Scale, Move parallel, Reverse)

/// Button + popover, not `Menu`: a Menu inside the bar's ViewThatFits crashes SwiftUI when the object changes
/// (undo/cut; confirmed in UI tests).
/// Shape tools as their own buttons in the object bar: cut/split, scale, parallel, and (lines) reverse direction.
/// Add point: double-tap the selected object's line. Merge: the Join (lines) / Merge (areas) button.
private struct ShapeEditButtons: View {
    @ObservedObject var model: WorkspaceModel
    let feature: Feature
    @State private var showingScale = false
    @State private var showingParallel = false
    @Environment(\.barCompact) private var compact

    var body: some View {
        if compact {
            folded
        } else {
            buttons
        }
    }

    /// Narrow bar: one scissors button with the same actions in a menu.
    private var folded: some View {
        let isLine = feature.kind == .line
        var items: [MenuItem] = [
            .action(isLine ? "Cut line" : "Split area", icon: "scissors") { model.startCut() },
            .action("Scale…", icon: "arrow.up.left.and.arrow.down.right") { showingScale = true },
            .action("Parallel…", icon: "line.3.horizontal") { showingParallel = true },
        ]
        if isLine { items.append(.action("Reverse line direction", icon: "arrow.left.arrow.right") { model.reverseSelected() }) }
        return SolidMenu(items: items, width: 240, plain: false) {
            Label("Edit shape", systemImage: "scissors")
        }
        .help("Edit shape: cut/split, scale, parallel, reverse")
        .accessibilityIdentifier("shapeTools")
        .popover(isPresented: $showingScale) { scalePanel }
        .popover(isPresented: $showingParallel) { parallelPanel }
    }

    private var scalePanel: some View {
        ScalePanel(model: model)
            .frame(width: 340)
            .padding(CP.Space.l)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(CP.paper)
    }

    private var parallelPanel: some View {
        ParallelPanel(model: model) { showingParallel = false }
            .frame(width: 340)
            .padding(CP.Space.l)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(CP.paper)
    }

    @ViewBuilder
    private var buttons: some View {
        let isLine = feature.kind == .line
        Button { model.startCut() } label: {
            Label(isLine ? "Cut line" : "Split area", systemImage: "scissors")
        }
        .help(isLine ? "Cut line: tap a point to cut it in two, or drag a box to cut out a part"
                     : "Split area: tap two points on the edge, or draw a rectangle, ellipse or path across it")
        .accessibilityIdentifier("shapeCut")
        GroupDivider()

        Button { showingScale = true } label: {
            Label("Scale…", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .help("Scale: enlarge/shrink the shape by a percentage; line width stays the same")
        .accessibilityIdentifier("shapeScale")
        .popover(isPresented: $showingScale) { scalePanel }
        GroupDivider()

        Button { showingParallel = true } label: {
            Label("Parallel…", systemImage: "line.3.horizontal")
        }
        .help("Parallel: copy or move the line/area sideways (roads, double tracks)")
        .accessibilityIdentifier("shapeParallel")
        .popover(isPresented: $showingParallel) { parallelPanel }

        if isLine {
            GroupDivider()
            Button { model.reverseSelected() } label: {
                Label("Reverse line direction", systemImage: "arrow.left.arrow.right")
            }
            .help("Reverse line direction (cliffs, fences, and other directional symbols)")
            .accessibilityIdentifier("shapeReverse")
        }
    }
}

/// OCAD Scale: resize the geometry proportionally around the object's center (line width unchanged).
private struct ScalePanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var original: Feature?
    @State private var before: [Feature]?
    @State private var percent = 100.0

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack {
                Text("Scale object").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                Spacer()
                Text(verbatim: "\(Int(percent.rounded()))%").font(CP.mono(17, weight: .semibold)).foregroundStyle(CP.ink)
            }
            Text("The shape is enlarged/shrunk proportionally from its center; line width stays the same.")
                .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            Slider(value: $percent, in: 10...400, step: 1) { editing in
                if editing {
                    before = model.features
                    original = model.selectedFeature
                } else {
                    if let before { model.commitFeatureEdit(from: before) }
                    before = nil
                    original = nil
                    percent = 100
                }
            }
            .onChange(of: percent) { _, v in
                if let original { model.scaleLive(original, by: v / 100) }
            }
            .accessibilityLabel("Scale")
            .help("Scale")
            .accessibilityValue("\(Int(percent.rounded())) percent")
            HStack(spacing: CP.Space.s) {
                ForEach([50.0, 90, 110, 150, 200], id: \.self) { k in
                    Button("\(Int(k))%") { model.scaleSelected(by: k / 100) }
                        .font(CP.mono(13, weight: .medium))
                        .buttonStyle(PastelButtonStyle(tone: CP.sand))
                }
            }
            Text("Buttons apply to the current size (can be repeated). The slider returns to 100% when released.")
                .font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
        }
    }
}

/// OCAD Move parallel: copy or move a line/area in parallel (double roads, track edges, layered boundaries).
private struct ParallelPanel: View {
    @ObservedObject var model: WorkspaceModel
    let dismiss: () -> Void
    @State private var mm = 1.0
    @State private var side = WorkspaceModel.ParallelSide.left

    private var meters: Double { model.project.sheet.groundMeters(forPaperMM: mm) }

    var body: some View {
        let isArea = model.selectedFeature?.kind == .area
        VStack(alignment: .leading, spacing: CP.Space.m) {
            Text("Parallel line").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
            Text(isArea ? "Area: left = inward, right = outward." : "Left/right follows the direction the line was drawn (reverse it if wrong).")
                .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            HStack {
                Text("Distance").font(.system(size: CP.fs(13))).foregroundStyle(CP.ink)
                Spacer()
                Stepper(value: $mm, in: 0.1...20, step: 0.1) {
                    Text(verbatim: "\(Fmt.mm(mm, decimals: 1)) · \(Fmt.meters(meters, decimals: 1))")
                        .font(CP.mono(13, weight: .medium))
                }
                .fixedSize()
            }
            Segmented("Side", selection: $side, WorkspaceModel.ParallelSide.allCases.map { s in
                .init(s, isArea ? (s == .left ? "Inward" : s == .right ? "Outward" : s.rawValue) : s.rawValue)
            })
            HStack(spacing: CP.Space.s) {
                Button {
                    model.parallelSelected(meters: meters, side: side, copy: true)
                    dismiss()
                } label: { Label("Parallel copy", systemImage: "plus.square.on.square") }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .accessibilityIdentifier("parallelCopy")
                Button {
                    model.parallelSelected(meters: meters, side: side, copy: false)
                    dismiss()
                } label: { Label("Move", systemImage: "arrow.right.to.line") }
                    .buttonStyle(PastelButtonStyle(tone: CP.sand))
                    .disabled(side == .both)
            }
            .font(.system(size: CP.fs(13), weight: .medium))
        }
    }
}

// MARK: - Change the selected object's symbol

/// OCAD "Change symbol" / OOM "Switch symbol": select an object → Change symbol → tap the new symbol.
/// "Change symbol" icon: symbol A → symbol B.
private struct SymbolSwapIcon: View {
    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "a.square")
            Image(systemName: "arrow.right").font(.system(size: CP.fs(8), weight: .heavy))
            Image(systemName: "b.square.fill")
        }
        .accessibilityHidden(true)
    }
}

private struct SymbolSwitchButton: View {
    @ObservedObject var model: WorkspaceModel
    @EnvironmentObject private var symbols: SymbolLibrary
    let feature: Feature
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Label {
                Text(feature.symbolCode.map { "Symbol \($0)" } ?? "Assign symbol")
            } icon: {
                SymbolSwapIcon()
            }
        }
        .popover(isPresented: $showing) {
            SymbolSwitchPicker(model: model, library: symbols) { showing = false }
                .frame(width: 380, height: 520)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(CP.paper)
        }
        .accessibilityLabel("Change object symbol")
        .help("Change object symbol")
        .accessibilityValue(feature.symbolCode ?? "no symbol")
    }
}

/// "Change symbol" for a multi-selection: every selected object gets the picked symbol (one undo step).
private struct MultiSymbolSwitchButton: View {
    @ObservedObject var model: WorkspaceModel
    @EnvironmentObject private var symbols: SymbolLibrary
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Label { Text("Change symbol") } icon: { SymbolSwapIcon() }
        }
        .popover(isPresented: $showing) {
            SymbolSwitchPicker(model: model, library: symbols, multi: true) { showing = false }
                .frame(width: 380, height: 520)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(CP.paper)
        }
        .accessibilityLabel("Change symbol of selected objects")
        .accessibilityIdentifier("changeSelectionSymbol")
        .help("Change symbol of the \(model.selectedIDs.count) selected objects")
    }
}

/// OCAD "Fill": selected line → pick an area symbol → new area below the line, the line is kept.
private struct FillAreaButton: View {
    @ObservedObject var model: WorkspaceModel
    @EnvironmentObject private var symbols: SymbolLibrary
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Label("Fill area", systemImage: "drop.halffull") }
            .help("Fill area")
            .popover(isPresented: $showing) {
                SymbolSwitchPicker(model: model, library: symbols, fill: true) { showing = false }
                    .frame(width: 380, height: 520)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(CP.paper)
            }
            .accessibilityIdentifier("fillArea")
    }
}

private struct SymbolSwitchPicker: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var library: SymbolLibrary
    /// Fill mode: area symbols only; picking one = create an area from the line (the line is kept).
    var fill = false
    /// Multi-selection: symbols any selected object can take; picking one changes them all.
    var multi = false
    let dismiss: () -> Void
    @State private var query = ""
    @State private var allSame = false

    /// Symbols from enabled sets, best set for the map first and sized for the map scale (like the Symbols panel:
    /// e.g. ISSprOM 1:4000 × 2.67 on a 1:1500 map), unique per code, whose kind matches the object.
    private var candidates: [MapSymbol] {
        guard let f = model.selectedFeature else { return [] }
        let targets = multi ? model.editableSelection : [f]
        let sets = library.preferredSets(for: model.project.sheet)
        var seen = Set<String>()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return sets.flatMap(\.symbols).filter { s in
            s.isEnabled && s.isDrawable && (fill ? s.kind == .area : targets.contains { $0.canSwitch(to: s) })
                && seen.insert(s.code).inserted
                && (q.isEmpty || s.code.hasPrefix(q) || s.name.lowercased().contains(q))
        }
    }

    /// Multi-selection: the symbol every selected object already has (marked as current), if they share one.
    private var sharedCode: String? {
        let codes = Set(model.editableSelection.map(\.symbolCode))
        return codes.count == 1 ? codes.first ?? nil : nil
    }

    var body: some View {
        let f = model.selectedFeature
        VStack(alignment: .leading, spacing: CP.Space.s) {
            Text(fill ? "Fill with area symbol" : "Change symbol").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
            if fill {
                Text("The line's shape is filled with a new area below it; the line symbol is kept. An open line is closed with a straight segment.")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            } else if multi {
                let sel = model.editableSelection
                let codes = Set(sel.compactMap(\.symbolCode))
                Text("\(sel.count) objects" + (codes.count == 1 ? " · all \(codes.first!)" : codes.isEmpty ? "" : " · \(codes.count) symbols"))
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted).lineLimit(1)
                Text("Every selected object gets the new symbol; shapes are kept. Objects of another kind (e.g. points for a line symbol) are left as they are.")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let f {
                Text(f.symbolCode.map { "Current: \($0) \(f.symbolName ?? "")" } ?? "Sketch object without a symbol")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted).lineLimit(1)
                Text(f.kind == .point ? "A point symbol can be changed to another point symbol."
                     : "Lines and areas can be swapped; the object's shape is kept.")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            }
            HStack(spacing: CP.Space.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(CP.inkMuted).font(.system(size: CP.fs(13)))
                TextField("Search code or name (e.g. 506 or path)", text: $query)
                    .font(.system(size: CP.fs(13)))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, CP.Space.s)
            .frame(height: 32)
            .searchFieldSurface()
            if !fill, !multi, let code = f?.symbolCode, model.sameSymbolCount > 1 {
                Toggle("All \(code) objects (\(model.sameSymbolCount))", isOn: $allSame)
                    .font(.system(size: CP.fs(13)))
                    .tint(CP.peach.strong)
            }
            let list = candidates
            if list.isEmpty {
                Text(library.enabledSets.isEmpty ? "No symbol sets enabled yet." : "No matching symbols.")
                    .font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(list, id: \.code) { s in
                            let current = !fill && (multi ? sharedCode == s.code : s.code == f?.symbolCode)
                            Button {
                                if fill { model.fillSelected(with: s) }
                                else if multi { model.switchSelectionSymbol(to: s) }
                                else { model.switchSelectedSymbol(to: s, allSame: allSame) }
                                dismiss()
                            } label: {
                                HStack(spacing: CP.Space.s) {
                                    SymbolSwatch(symbol: s)
                                    Text(s.code).font(CP.mono(12, weight: .medium)).foregroundStyle(CP.ink).frame(width: 48, alignment: .leading)
                                    Text(s.name).font(.system(size: CP.fs(13))).foregroundStyle(CP.ink).lineLimit(1)
                                    Spacer(minLength: 4)
                                    if !multi, s.kind.rawValue != f?.kind.rawValue {
                                        Text(s.kind.label).font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
                                    }
                                    if current { Image(systemName: "checkmark").foregroundStyle(CP.peach.strong) }
                                }
                                .padding(.vertical, 6).padding(.horizontal, CP.Space.s)
                                .contentShape(Rectangle())
                                .background(current ? CP.peach.fill : .clear, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .disabled(current && !allSame)
                            .accessibilityLabel("\(s.code) \(s.name), \(s.kind.label)")
                        }
                    }
                }
            }
        }
        .padding(CP.Space.l)
    }
}

private func degreesText(_ d: Double) -> String {
    d.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(d))°" : String(format: "%.1f°", locale: Locale(identifier: "en_US_POSIX"), d)
}

// MARK: - Convert to Sharp / Smooth / Smart

/// Three point-type buttons for the active point in the Node Tool (like Affinity Designer).
private struct NodeStylePicker: View {
    @ObservedObject var model: WorkspaceModel
    let current: NodeStyle

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NodeStyle.allCases, id: \.self) { style in
                Button { model.convertSelectedNode(to: style) } label: {
                    NodeStyleIcon(style: style)
                        .frame(width: 34, height: 30)
                        .background(style == current ? CP.sky.fill : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(style == current ? CP.sky.strong : CP.ink)
                .accessibilityLabel(style.title)
                .accessibilityAddTraits(style == current ? .isSelected : [])
                .help("\(style.title): \(style.hint)")
            }
        }
        .padding(2)
        .background(CP.line.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension NodeStyle {
    var title: String {
        switch self {
        case .sharp: return "Convert to Sharp"
        case .smooth: return "Convert to Smooth"
        case .smart: return "Convert to Smart"
        }
    }

    var hint: String {
        switch self {
        case .sharp: return "sharp corner, no handles"
        case .smooth: return "smooth curve, aligned handles"
        case .smart: return "automatic curve following neighboring points"
        }
    }
}

/// Point type icon: sharp = Λ with a filled point, smooth = curve + horizontal handle, smart = curve + hollow point.
private struct NodeStyleIcon: View {
    let style: NodeStyle

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let top = CGPoint(x: w / 2, y: h * 0.3)
            let left = CGPoint(x: w * 0.22, y: h * 0.82), right = CGPoint(x: w * 0.78, y: h * 0.82)
            var path = Path()
            path.move(to: left)
            switch style {
            case .sharp:
                path.addLine(to: top)
                path.addLine(to: right)
            case .smooth, .smart:
                path.addCurve(to: top, control1: CGPoint(x: left.x, y: h * 0.5), control2: CGPoint(x: w * 0.3, y: top.y))
                path.addCurve(to: right, control1: CGPoint(x: w * 0.7, y: top.y), control2: CGPoint(x: right.x, y: h * 0.5))
            }
            ctx.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            let r: CGFloat = 3
            let dot = Path(ellipseIn: CGRect(x: top.x - r, y: top.y - r, width: 2 * r, height: 2 * r))
            switch style {
            case .sharp:
                ctx.fill(dot, with: .foreground)
            case .smooth:
                var handle = Path()
                handle.move(to: CGPoint(x: w * 0.3, y: top.y))
                handle.addLine(to: CGPoint(x: w * 0.7, y: top.y))
                ctx.stroke(handle, with: .foreground, lineWidth: 1)
                for x in [w * 0.3, w * 0.7] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: top.y - 1.8, width: 3.6, height: 3.6)), with: .foreground)
                }
                ctx.fill(dot, with: .foreground)
            case .smart:
                ctx.fill(dot, with: .color(CP.paper))
                ctx.stroke(dot, with: .foreground, lineWidth: 1.4)
            }
        }
    }
}

/// Merge button (prominent, name always shown) when objects with the same symbol meet.
private struct MergeButton: View {
    let title: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(title, systemImage: "link") }
            .labelStyle(.titleAndIcon)
            .buttonStyle(PastelButtonStyle(tone: CP.sky))
            .help("\(help) (⌘J)")
            .keyboardShortcut("j", modifiers: .command)
    }
}

/// 📖 button that opens the symbol guide (ISOM / ISSprOM) for a symbol; highlighted while it shows that symbol.
struct SymbolGuideButton: View {
    var isOpen: Bool
    var label: String? = nil
    /// Inside a `ButtonGroup` (object bar): the group's button style and height.
    var inGroup = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            if let label {
                Label(label, systemImage: isOpen ? "book.fill" : "book")
            } else {
                Image(systemName: isOpen ? "book.fill" : "book")
            }
        }
        .modifier(GuideButtonStyle(compact: label == nil, active: isOpen, inGroup: inGroup))
        .accessibilityLabel(isOpen ? "Close symbol guide" : "Symbol guide")
        .help("Symbol guide: ISOM / ISSprOM rules for this symbol (⇧⌘/)")
    }
}

private struct GuideButtonStyle: ViewModifier {
    var compact: Bool
    var active: Bool
    var inGroup = false
    func body(content: Content) -> some View {
        if inGroup {
            content.buttonStyle(GroupedButtonStyle(isActive: active))
        } else if compact {
            content.buttonStyle(ToolButtonStyle(isActive: active))
        } else {
            content
        }
    }
}

/// iPad without a license key: the project is view-only.
private struct ViewOnlyBanner: View {
    var body: some View {
        HStack(spacing: CP.Space.m) {
            Image(systemName: "eye").foregroundStyle(CP.sky.strong)
            VStack(alignment: .leading, spacing: 1) {
                Text("View only").font(.system(size: CP.fs(14), weight: .semibold)).foregroundStyle(CP.ink)
                Text("Activate a license key to edit. You can still pan, zoom, and export to PDF.")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            }
            Button("Activate") { LicensePresenter.present(nil) }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .accessibilityIdentifier("viewOnlyActivate")
        }
        .padding(.horizontal, CP.Space.l)
        .padding(.vertical, CP.Space.s)
        .background(CP.paper, in: Capsule())
        .overlay(Capsule().strokeBorder(CP.line))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewOnlyBanner")
    }
}

/// iPad: a small grip on the left edge of the right panel. Tap or swipe right = hide the panel; with the panel hidden
/// the grip stays at the screen edge: tap or swipe left = show it again.
struct PanelEdgeHandle: View {
    @Binding var isOpen: Bool

    var body: some View {
        Capsule()
            .fill(CP.inkMuted.opacity(0.55))
            .frame(width: 4, height: 34)
            .frame(width: 20, height: 64)
            .background(CP.paper, in: UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10).strokeBorder(CP.line))
            .shadow(color: .black.opacity(0.08), radius: 2, x: -1)
            .contentShape(Rectangle().inset(by: -10))
            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { isOpen.toggle() } }
            .gesture(DragGesture(minimumDistance: 6).onEnded { v in
                let dx = v.predictedEndTranslation.width
                withAnimation(.easeOut(duration: 0.2)) {
                    if isOpen && dx > 30 { isOpen = false } else if !isOpen && dx < -30 { isOpen = true }
                }
            })
            .accessibilityElement()
            .accessibilityLabel(isOpen ? "Hide panel" : "Show panel")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("panelHandle")
    }
}
