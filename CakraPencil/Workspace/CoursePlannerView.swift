import CakraCore
import PDFKit
import SwiftUI

/// Course Planner page (like Purple Pen): map with the course overprint, a dedicated tool rail
/// (navigate, start, control, finish), and the full Course panel: Courses · Controls · Descriptions · Report.
/// Uses the same workspace model, so undo, autosave, and map data stay shared.
struct CoursePlannerView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var showingExport = false
    /// Mac: bottom edge of the toolbar strip; the map canvas starts below it (frame not covered).
    @State private var bandBottom: CGFloat = 0
    @State private var importingMap = false
    @State private var showingPreview = false
    @State private var importingImage = false
    @State private var tab = CoursePlannerView.initialTab

    /// DEBUG `-cp-course-no-panel`: no panel, to isolate the panel's render cost in performance tests.
    private static var hidePanelForProbe: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-cp-course-no-panel")
        #else
        false
        #endif
    }

    private static var initialTab: CourseTab {
        #if DEBUG
        // For performance tests/screenshots: `-cp-course-tab Report`.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-cp-course-tab"), i + 1 < args.count, let t = CourseTab(rawValue: args[i + 1]) { return t }
        #endif
        return .courses
    }

    var body: some View {
        ZStack {
            MapCanvas(model: model, role: .course)
                .padding(.top, CP.isMac ? bandBottom : 0)
                .ignoresSafeArea(edges: CP.isMac && bandBottom > 0 ? [.bottom, .horizontal] : .all)

            VStack(spacing: 0) {
                CourseTopBar(model: model, showingExport: $showingExport, importingMap: $importingMap, showingPreview: $showingPreview)
                if CP.isMac {
                    // Mac: tools + map controls + status sit in the top toolbar strip; right panel below it.
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: CP.Space.s) {
                            CourseToolRail(model: model, importingImage: $importingImage, horizontal: true)
                            BandSeparator()
                            MapControls(model: model, horizontal: true, showsCompass: false)
                            Spacer(minLength: 0)
                            DigitalCompass(model: model, live: model.live, embedded: true).modifier(BandCornerPadding())
                        }
                        .padding(.horizontal, CP.Space.s)
                        .padding(.vertical, 2)
                        CourseStatusBar(model: model)
                    }
                    .modifier(MacBand())
                    .modifier(BandBottomReader(space: "course"))
                    // Right panel spans the full right side, from below the strip to the bottom of the window.
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if !Self.hidePanelForProbe {
                            CoursePlannerPanel(model: model, tab: $tab, showingExport: $showingExport, showingPreview: $showingPreview,
                                               importingImage: $importingImage)
                                .frame(width: 400)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                HStack(alignment: .top, spacing: 0) {
                    CourseToolRail(model: model, importingImage: $importingImage)
                        .padding(CP.Space.m)
                    Spacer(minLength: 0)
                    VStack {
                        Spacer(minLength: 0)
                        MapControls(model: model)
                    }
                    .padding(.vertical, CP.Space.m)
                    if !Self.hidePanelForProbe {
                        CoursePlannerPanel(model: model, tab: $tab, showingExport: $showingExport, showingPreview: $showingPreview,
                                           importingImage: $importingImage)
                            .frame(width: 400)
                            .padding(CP.Space.m)
                    }
                }
                CourseStatusBar(model: model)
                    .padding(.horizontal, CP.Space.m)
                    .padding(.bottom, CP.Space.m)
                }
            }

            if let notice = model.notice {
                VStack {
                    // Mac: the tool strip is at the top, so messages appear at the bottom.
                    if CP.isMac { Spacer() }
                    Toast(text: notice) { model.notice = nil }
                        .padding(CP.isMac ? .bottom : .top, CP.isMac ? CP.Space.xl : 64)
                    if !CP.isMac { Spacer() }
                }
            }
        }
        .background(CP.paper)
        .coordinateSpace(name: "course")
        .onPreferenceChange(BandBottomKey.self) { bandBottom = $0 }
        .sheet(isPresented: $showingExport) {
            ExportSheet(model: model, mode: .courses)
        }
        .sheet(isPresented: $showingPreview) {
            CoursePreviewSheet(model: model)
        }
        .fileImporter(isPresented: $importingMap, allowedContentTypes: LayerPanel.mapFileTypes) { result in
            if case let .success(url) = result { Task { await model.importOcad(from: url) } }
        }
        .fileImporter(isPresented: $model.showsCourseImporter, allowedContentTypes: [.cakraProject] + LayerPanel.mapFileTypes) { result in
            if case let .success(url) = result { Task { await model.importCourseFile(from: url) } }
        }
        .alert("Courses outside this map", isPresented: Binding(get: { model.courseImportOutside != nil }, set: { if !$0 { model.courseImportOutside = nil } })) {
            Button("Undo import", role: .destructive) { model.undo() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text(model.courseImportOutside ?? "")
        }
        // Object selected on the map → show its editor in the Objects tab.
        .onChange(of: model.selectedCourseItemID) { _, id in if id != nil { tab = .items } }
    }
}

enum CourseTab: String, CaseIterable {
    case courses = "Courses"
    case controls = "Controls"
    case items = "Objects"
    case descriptions = "Descriptions"
    case report = "Report"
}

// MARK: - Top bar

private struct CourseTopBar: View {
    @ObservedObject var model: WorkspaceModel
    @Binding var showingExport: Bool
    @Binding var importingMap: Bool
    @Binding var showingPreview: Bool

    var body: some View {
        HStack(spacing: CP.Space.m) {
            Button { model.closeCoursePlanner() } label: {
                Label("Map workspace", systemImage: "chevron.left").font(.system(size: CP.fs(15), weight: .medium)).lineLimit(1).fixedSize()
            }
            .buttonStyle(.bordered)
            .tint(CP.ink)
            .accessibilityLabel("Back to map workspace")
            .help("Back to map workspace")

            Image(systemName: "flag.2.crossed").foregroundStyle(Color(hexString: "#A626FF")).font(.system(size: CP.fs(18), weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Course Planner").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink).lineLimit(1).fixedSize()
                Text(subtitle).font(CP.mono(12)).foregroundStyle(CP.inkMuted).lineLimit(1)
            }
            .layoutPriority(-1)
            Spacer(minLength: 0)
            // Enough width: icon + text; narrow screen (iPad portrait): icon only.
            ViewThatFits(in: .horizontal) {
                actions.labelStyle(.titleAndIcon)
                actions.labelStyle(.iconOnly)
            }
            .layoutPriority(1)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(ToolButtonStyle())
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityLabel("Undo")
                .help("Undo")
                .accessibilityIdentifier("courseUndo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(ToolButtonStyle())
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityLabel("Redo")
                .help("Redo")
            Button("Export") { showingExport = true }
                .buttonStyle(PrimaryButtonStyle())
                .lineLimit(1)
                .fixedSize()
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.courseSet.controls.isEmpty)
                .accessibilityIdentifier("courseExport")
        }
        .padding(.horizontal, CP.Space.m)
        .padding(.vertical, CP.Space.s)
        .background(CP.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(CP.line).frame(height: 1) }
    }

    private var actions: some View {
        HStack(spacing: CP.Space.s) {
            Button { model.showsCourseImporter = true } label: {
                Label("Import course", systemImage: "flag.2.crossed").font(.system(size: CP.fs(14), weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(Color(hexString: "#A626FF"))
            .help("Import controls and courses from an OCCA project (.occa), an OCAD course setting file (.ocd), or the course symbols of an OOM map (.omap, .xmap)")
            .accessibilityLabel("Import course")
            .accessibilityIdentifier("importCourse")
            Button { importingMap = true } label: {
                Label("Import map", systemImage: "square.and.arrow.down").font(.system(size: CP.fs(14), weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(CP.ink)
            .help("Use a georeferenced OCAD / OOM map (.ocd, .omap, .xmap) as the course background")
            .accessibilityLabel("Import OCAD or OOM map")
            Button { showingPreview = true } label: {
                Label("Preview", systemImage: "eye").font(.system(size: CP.fs(14), weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(Color(hexString: "#A626FF"))
            .disabled(model.courseSet.controls.isEmpty)
            .keyboardShortcut("p", modifiers: .command)
            .accessibilityLabel("Preview control descriptions")
            .help("Preview control descriptions")
            SaveBadge(state: model.saveState)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var subtitle: String {
        let set = model.courseSet
        let standard = model.project.sheet.scaleDenominator <= 5000 ? "ISSprOM" : "ISOM"
        let event = set.eventTitle.isEmpty ? model.project.name : set.eventTitle
        return "\(event) · 1:\(model.project.sheet.scaleDenominator) · \(standard) · \(set.courses.count) courses · \(set.controls.filter { $0.kind == .control }.count) controls"
    }
}

// MARK: - Tool rail

private struct CourseToolRail: View {
    @ObservedObject var model: WorkspaceModel
    @Binding var importingImage: Bool
    /// Mac: one row in the top toolbar strip.
    var horizontal = false

    var body: some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: CP.Space.xs)) : AnyLayout(VStackLayout(spacing: CP.Space.xs))
        return layout {
            Button { model.useCourseTool(nil) } label: { Image(systemName: "hand.raised") }
                .buttonStyle(ToolButtonStyle(isActive: model.tool == .navigate))
                .keyboardShortcut("h", modifiers: [])
                .accessibilityLabel("Navigate")
                .help("Navigate")
            divider
            place(.start, key: "s")
            place(.control, key: "k")
            place(.finish, key: "f")
            divider
            item(.text, key: "t")
            item(.rectangle, key: "r")
            item(.ellipse, key: "e")
            item(.line, key: "l")
            Button { importingImage = true } label: { Image(systemName: "photo.badge.plus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("i", modifiers: [])
                .accessibilityLabel("Add image")
                .help("Add JPG/PNG image (max. 10 MB, 8000 px, 10 images) (I)")
            divider
            Button { model.zoomToCourse() } label: { Image(systemName: "scope") }
                .buttonStyle(ToolButtonStyle())
                .accessibilityLabel("Zoom to course")
            Button { model.mapCommand = MapCommand(kind: .zoomToFrame) } label: { Image(systemName: "rectangle.dashed") }
                .buttonStyle(ToolButtonStyle())
                .accessibilityLabel("Zoom to frame")
                .help("Zoom to map frame")
        }
        .modifier(DockChrome())
        .fileImporter(isPresented: $importingImage, allowedContentTypes: [.jpeg, .png]) { result in
            if case let .success(url) = result { Task { await model.importCourseImage(from: url, at: nil) } }
        }
    }

    /// Course object tools (text, shapes).
    private func item(_ kind: CourseItem.Kind, key: Character) -> some View {
        let active = model.tool == .control && model.courseItemTool == kind
        return Button { model.useCourseItemTool(kind) } label: { Image(systemName: kind.systemImage) }
            .buttonStyle(ToolButtonStyle(isActive: active))
            .keyboardShortcut(KeyEquivalent(key), modifiers: [])
            .accessibilityLabel("\(kind.label) tool")
            .help("\(kind.label) (\(String(key).uppercased()))")
    }

    private func place(_ kind: ControlKind, key: Character) -> some View {
        let active = model.tool == .control && model.courseItemTool == nil && model.controlPlacement == kind
        return Button { model.useCourseTool(kind) } label: {
            ControlGlyph(kind: kind, color: active ? .white : Color(hexString: "#A626FF")).frame(width: 22, height: 22)
        }
        .buttonStyle(ToolButtonStyle(isActive: active))
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
        .accessibilityLabel("Place \(kind.label)")
        .help("Place \(kind.label) (\(String(key).uppercased()))")
    }

    private var divider: some View {
        Rectangle().fill(CP.line)
            .frame(width: horizontal ? 1 : 28, height: horizontal ? 28 : 1)
            .padding(horizontal ? .horizontal : .vertical, CP.Space.xs)
    }
}

// MARK: - Bottom status: tool hint + map intensity

/// Status: floating panel at the bottom (iPad) or a row in the top toolbar strip (Mac).
private struct StatusChrome: ViewModifier {
    @Environment(\.docked) private var docked

    func body(content: Content) -> some View {
        if docked {
            content
                .padding(.horizontal, CP.Space.m)
                .padding(.vertical, CP.Space.xs)
                .overlay(alignment: .top) { Rectangle().fill(CP.line).frame(height: 1) }
        } else {
            content
                .padding(.horizontal, CP.Space.l)
                .padding(.vertical, CP.Space.s)
                .cpPanel()
        }
    }
}

private struct CourseStatusBar: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        HStack(spacing: CP.Space.l) {
            Text(hint).font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted).lineLimit(2)
            Spacer(minLength: CP.Space.m)
            if let id = model.selectedControlID, let c = model.courseSet.control(id) {
                ControlSizeStepper(model: model, control: c)
            }
            Image(systemName: "map").foregroundStyle(CP.inkMuted)
                .help("Background: the drawn map. Satellite imagery is not used on the Course page.")
                .accessibilityLabel("Background: the drawn map, no satellite imagery")
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(CP.inkMuted)
                .accessibilityHidden(true)
            Slider(value: $model.courseMapIntensity, in: 0.2...1)
                .frame(width: 130)
                .tint(CP.ink)
                .accessibilityLabel("Map intensity")
            Text(verbatim: "\(Int((model.courseMapIntensity * 100).rounded()))%").font(CP.mono(12)).foregroundStyle(CP.ink).frame(width: 40)
        }
        .modifier(StatusChrome())
    }

    private var hint: String {
        guard model.tool == .control else { return "Navigate: pan, pinch, rotate the map" }
        switch model.courseItemTool {
        case .text?: return "Text: tap the map to place text (edit it in the Objects tab) · drag object = move"
        case .rectangle?, .ellipse?: return "\(model.courseItemTool!.label): drag from corner to corner · drag object = move"
        case .line?: return "Line: drag from start point to end point · drag object = move"
        default: break
        }
        let target = model.selectedCourse.map { "course \($0.name)" } ?? "all controls"
        return "Tap the map: new \(model.controlPlacement.label.lowercased()) (\(target)) · drag = move"
    }
}

// MARK: - Course panel

struct CoursePlannerPanel: View {
    @ObservedObject var model: WorkspaceModel
    @Binding var tab: CourseTab
    @Binding var showingExport: Bool
    @Binding var showingPreview: Bool
    @Binding var importingImage: Bool
    @State private var editingControl: ControlPoint?
    @State private var renaming: Course?
    @State private var newName = ""
    @State private var eventTitle = ""
    @State private var organizer = ""
    /// Stable binding (not a new `.constant` each render) so the List doesn't reload every row.
    @State private var editMode = EditMode.inactive
    private var reordering: Bool { editMode == .active }

    private var set: CourseSet { model.courseSet }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Course panel", selection: $tab) {
                ForEach(CourseTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], CP.Space.l)
            .padding(.bottom, CP.Space.s)

            switch tab {
            case .courses: coursesTab
            case .controls: controlsTab
            case .items: itemsTab
            case .descriptions: descriptionsTab
            case .report: reportTab
            }
        }
        .modifier(SidePanelChrome())
        .onAppear { eventTitle = set.eventTitle; organizer = set.organizer ?? "" }
        .sheet(item: $editingControl) { c in ControlEditor(model: model, controlID: c.id) }
        .alert("Rename course", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let c = renaming, !name.isEmpty { model.updateCourse(c.id) { $0.name = name } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: Courses tab

    /// ScrollView + Equatable rows (not List): a data change only redraws the rows that changed.
    /// Performance test (Release): changing course data 89 ms → a few ms per change.
    private var coursesTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CP.Space.l) {
                group("Event") {
                    VStack(alignment: .leading, spacing: CP.Space.s) {
                    TextField("Event name (e.g. Regional Sprint Championship 2026)", text: $eventTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.setEventTitle(eventTitle) }
                        .onDisappear { if eventTitle != set.eventTitle { model.setEventTitle(eventTitle) } }
                    TextField("Organizer name (e.g. Makopala University …)", text: $organizer)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.setOrganizer(organizer) }
                        .onDisappear { model.setOrganizer(organizer) }
                        .accessibilityIdentifier("organizer")
                    Text("The organizer is printed below the event name on the control descriptions.")
                        .font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
                        .padding(.bottom, CP.Space.xs)
                    }
                    .padding(.vertical, CP.Space.xs)
                }

                group("Courses (\(set.courses.count))") {
                    VStack(spacing: 0) {
                        courseCard(nil)
                        ForEach(set.courses) { c in
                            Divider().overlay(CP.line)
                            courseCard(c)
                        }
                        Divider().overlay(CP.line)
                        Button { model.addCourse() } label: {
                            Label("New course", systemImage: "plus.circle.fill")
                                .font(.system(size: CP.fs(15), weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(hexString: "#A626FF"))
                        Divider().overlay(CP.line)
                        Button { model.showsCourseImporter = true } label: {
                            Label("Import course…", systemImage: "square.and.arrow.down")
                                .font(.system(size: CP.fs(15), weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(hexString: "#A626FF"))
                        .help(".occa, .ocd (OCAD course setting), .omap / .xmap (OOM course symbols)")
                        .accessibilityIdentifier("importCourseRow")
                    }
                }

                if let course = model.selectedCourse {
                    courseDetail(course)
                    courseControls(course)
                }
            }
            .padding(CP.Space.l)
        }
    }

    /// Inset-grouped style group: small title + card.
    private func group<Content: View, Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() },
                                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CP.Space.xs) {
            HStack {
                Text(title).font(.system(size: CP.fs(13), weight: .medium)).foregroundStyle(CP.inkMuted)
                Spacer()
                accessory()
            }
            .padding(.horizontal, CP.Space.xs)
            content()
                .padding(.horizontal, CP.Space.m)
                .padding(.vertical, CP.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func courseCard(_ course: Course?) -> some View {
        let controls = course.map { set.controls(of: $0).filter { $0.kind == .control }.count } ?? set.controls.filter { $0.kind == .control }.count
        let subtitle = course.map { c in
            "\(c.kind == .score ? "Score" : Fmt.km(set.length(of: c))) · \(controls) controls · \(c.competitors) competitors"
        } ?? "\(controls) controls on the map"
        return CourseCardView(name: course?.name ?? "All controls", subtitle: subtitle, selected: model.selectedCourseID == course?.id,
                              isCourse: course != nil, outsideMap: course.map(model.isOutsideMap) ?? false) { model.selectedCourseID = course?.id }
            .equatable()
            .contextMenu {
                if let c = course {
                    Button { newName = c.name; renaming = c } label: { Label("Rename", systemImage: "pencil") }
                    Button { model.duplicateCourse(c.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { model.selectedCourseID = c.id; model.zoomToCourse() } label: { Label("Zoom to course", systemImage: "scope") }
                    Divider()
                    Button(role: .destructive) { model.deleteCourse(c.id) } label: { Label("Delete course", systemImage: "trash") }
                }
            }
    }

    private func courseDetail(_ course: Course) -> some View {
        group("Course \(course.name)", accessory: {
            Menu {
                Button { newName = course.name; renaming = course } label: { Label("Rename", systemImage: "pencil") }
                Button { model.duplicateCourse(course.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button { model.zoomToCourse() } label: { Label("Zoom to course", systemImage: "scope") }
                Divider()
                Button(role: .destructive) { model.deleteCourse(course.id) } label: { Label("Delete course", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Course menu \(course.name)")
                .help("Course menu \(course.name)")
        }) {
            VStack(alignment: .leading, spacing: CP.Space.s) {
                CourseNameField(model: model, course: course)
                    .id(course.id)
                    .padding(.top, CP.Space.xs)
                Picker("Type", selection: Binding(get: { course.kind }, set: { k in model.updateCourse(course.id) { $0.kind = k } })) {
                    ForEach(CourseKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, CP.Space.xs)
                HStack {
                    stat(course.kind == .score ? "Score" : Fmt.km(set.length(of: course)), "length")
                    Spacer()
                    stat("\(set.controls(of: course).filter { $0.kind == .control }.count)", "controls")
                    Spacer()
                    stat(course.climbM.map { "\($0) m" } ?? "–", "climb")
                }
                Divider().overlay(CP.line)
                Stepper(value: Binding(get: { course.competitors }, set: { v in model.updateCourse(course.id) { $0.competitors = max(0, v) } }),
                        in: 0...5000, step: 5) {
                    HStack {
                        Text("Competitors")
                        Spacer()
                        Text(verbatim: "\(course.competitors)").font(CP.mono(14))
                    }
                }
                .accessibilityLabel("Number of competitors")
                Stepper(value: Binding(get: { course.climbM ?? 0 }, set: { v in model.updateCourse(course.id) { $0.climbM = v > 0 ? v : nil } }),
                        in: 0...3000, step: 5) {
                    HStack {
                        Text("Climb")
                        Spacer()
                        Text(verbatim: "\(course.climbM ?? 0) m").font(CP.mono(14))
                    }
                }
                .padding(.bottom, CP.Space.xs)
            }
        }
    }

    private func courseControls(_ course: Course) -> some View {
        let list = set.controls(of: course)
        let legs = set.legLengths(of: course)
        var n = 0
        let numbers: [String] = list.map { c in
            guard c.kind == .control else { return "" }
            n += 1
            return course.kind == .score ? "" : "\(n)"
        }
        return VStack(alignment: .leading, spacing: CP.Space.xs) {
            group("Control order", accessory: {
                Button(reordering ? "Done" : "Reorder") { editMode = reordering ? .inactive : .active }
                    .font(.system(size: CP.fs(13), weight: .semibold))
                    .disabled(list.count < 2)
            }) {
                VStack(spacing: 0) {
                    if list.isEmpty {
                        Text("Select Start in the left rail and tap the map, then Control, and end with Finish.")
                            .font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted).padding(.vertical, CP.Space.s)
                    }
                    ForEach(Array(list.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Divider().overlay(CP.line) }
                        HStack(spacing: CP.Space.xs) {
                            controlRow(c, number: numbers[i], detail: i > 0 && course.kind == .normal ? "\(Int(legs[i - 1].rounded())) m" : nil)
                            if reordering {
                                Button { model.moveSelectedCourseControls(from: [i], to: i - 1) } label: { Image(systemName: "arrow.up") }
                                    .disabled(i == 0)
                                    .accessibilityLabel("Move up \(c.label(in: set))")
                                    .help("Move up \(c.label(in: set))")
                                Button { model.moveSelectedCourseControls(from: [i], to: i + 2) } label: { Image(systemName: "arrow.down") }
                                    .disabled(i == list.count - 1)
                                    .accessibilityLabel("Move down \(c.label(in: set))")
                                    .help("Move down \(c.label(in: set))")
                                Button(role: .destructive) { model.removeFromSelectedCourse(at: i) } label: { Image(systemName: "minus.circle.fill") }
                                    .accessibilityLabel("Remove \(c.label(in: set)) from course")
                                    .help("Remove \(c.label(in: set)) from course")
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Text(reordering ? "↑ ↓ change the order, ⊖ removes from the course (the control stays on the map)." : "Tap a row for the code and IOF description. Reorder to move or remove controls.")
                .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                .padding(.horizontal, CP.Space.xs)
        }
    }

    private func controlRow(_ c: ControlPoint, number: String, detail: String?) -> some View {
        ControlRowView(control: c, label: c.label(in: set), number: number, detail: detail,
                       selected: model.selectedControlID == c.id) {
            model.selectedControlID = c.id
            editingControl = c
        }
        .equatable()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value).font(CP.mono(17, weight: .semibold)).foregroundStyle(CP.ink)
            Text(label).font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
        }
    }

    // MARK: Controls tab

    private var controlsTab: some View {
        let loads = Dictionary(uniqueKeysWithValues: set.controlLoads().map { ($0.controlID, $0) })
        return List {
            Section {
                Stepper(value: Binding(get: { set.firstCode }, set: { v in model.editCourses { $0.firstCode = v } }), in: 31...200) {
                    HStack {
                        Text("First code")
                        Spacer()
                        Text(verbatim: "\(set.firstCode)").font(CP.mono(14))
                    }
                }
                Toggle("Skip codes that read differently upside down (66/99, 68/89)",
                       isOn: Binding(get: { set.avoidAmbiguousCodes }, set: { on in model.editCourses { $0.avoidAmbiguousCodes = on } }))
                    .tint(CP.sage.strong)
                Button { model.renumberControls() } label: { Label("Renumber all codes", systemImage: "number") }
                    .disabled(set.controls.isEmpty)
            } header: { Text("Code numbering") } footer: {
                Text("Renumbering follows course order (first course first). Codes 31–255 match SPORTident/Emit units.")
            }

            sizeSection

            Section {
                if set.controls.isEmpty {
                    Text("No controls yet. Select Control in the left rail and tap the map.").font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                }
                ForEach(set.controls) { c in
                    let using = set.courses.filter { $0.controlIDs.contains(c.id) }.map(\.name)
                    let visits = loads[c.id]?.visits ?? 0
                    controlRow(c, number: "", detail: using.isEmpty ? "unused" : "\(using.joined(separator: ",")) · \(visits)")
                }
                .onDelete { idx in idx.map { set.controls[$0].id }.forEach(model.deleteControl) }
            } header: { Text("All controls (\(set.controls.count))") } footer: {
                Text("Right: courses using it · number of competitors. Swipe left to delete from the map and all courses.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .textCase(nil)
    }

    private var sizeSection: some View {
        let a = set.effectiveAppearance
        let custom = set.controls.filter { $0.sizeFactor != nil }.count
        return Section {
            percentStepper("Control circle, start, finish", a.controlScale) { v in model.updateAppearance { $0.controlScale = v } }
            percentStepper("Control number", a.numberScale) { v in model.updateAppearance { $0.numberScale = v } }
            percentStepper("Line width", a.lineScale) { v in model.updateAppearance { $0.lineScale = v } }
            if !a.isStandard || custom > 0 {
                Button { model.resetAllControlSizes() } label: { Label("Reset to IOF standard", systemImage: "arrow.counterclockwise") }
            }
        } header: { Text("Course symbol size").textCase(nil) } footer: {
            let base = model.courseStyle
            let scale = model.project.sheet.scaleDenominator, std = MapStandard.for(scale: scale), k = std.enlargement(scale: scale)
            Text("100% = \(std.label) standard\(k > 1.001 ? " enlarged to \(Int((k * 100).rounded()))% for 1:\(scale)" : ""): circle \(Fmt.mm(base.controlDiameterMM, decimals: 1)), start \(Fmt.mm(base.startSideMM, decimals: 1)), number \(Fmt.mm(base.numberHeightMM, decimals: 1)), line \(Fmt.mm(base.lineWidthMM)).\(custom > 0 ? " \(custom) controls have their own size (set in the control editor)." : "")")
        }
    }

    private func percentStepper(_ title: String, _ value: Double, set: @escaping (Double) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: set), in: CourseAppearance.range, step: 0.05) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(Int((value * 100).rounded()))%").font(CP.mono(14))
                    .foregroundStyle(abs(value - 1) < 0.001 ? CP.inkMuted : CP.ink)
            }
        }
        .accessibilityLabel("\(title), \(Int((value * 100).rounded())) percent")
    }

    // MARK: Descriptions tab

    private var descriptionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.m) {
                if set.controls.isEmpty {
                    Text("Place controls and create a course first in the Courses tab.").font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                } else {
                    // "All controls" (master) = selectedCourseID nil, same as the selection in the Courses tab.
                    Picker("Course", selection: Binding(get: { model.selectedCourseID }, set: { model.selectedCourseID = $0 })) {
                        Text("All controls").tag(UUID?.none)
                        ForEach(set.courses) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .pickerStyle(.segmented)
                    let course = model.selectedCourse
                    let sheet = DescriptionSheet(set, course: course)
                    DescriptionSheetView(sheet: sheet,
                                         symbols: set.effectivePrintLayout.descriptionSymbols,
                                         ink: set.effectivePrintLayout.descriptionColor == .purple
                                            ? Color(hexString: set.effectivePrintLayout.descriptionColor.hex) : CP.ink) { index in
                        let list = course.map { set.controls(of: $0) } ?? DescriptionSheet.allControlsOrder(set)
                        if list.indices.contains(index) { editingControl = list[index] }
                    }
                    Text(course == nil
                         ? "All controls (master): codes in column B, sorted by code, no legs. Tap a row to edit the description (columns C–H)."
                         : "Tap a row to edit the description (columns C–H). IOF 2018 symbols; printed on the competition map (set position, columns, and style in Print layout).")
                        .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    Button { showingPreview = true } label: {
                        Label("Preview competition map (as printed)", systemImage: "eye").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(hexString: "#A626FF"))
                    .accessibilityLabel("Preview description PDF")
                    .help("Preview description PDF")
                    Button { showingExport = true } label: {
                        Label("Export PDF + descriptions…", systemImage: "doc.richtext").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Divider().overlay(CP.line).padding(.vertical, CP.Space.xs)
                    PrintLayoutSection(model: model, sheet: sheet)
                }
            }
            .padding(CP.Space.l)
        }
    }

    // MARK: Objects tab (text, shapes, images)

    private var itemsTab: some View {
        let items = set.allItems
        return ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.l) {
                group("Add to map") {
                    HStack(spacing: CP.Space.s) {
                        ForEach([CourseItem.Kind.text, .rectangle, .ellipse, .line], id: \.self) { kind in
                            Button { model.useCourseItemTool(kind) } label: {
                                Label(kind.label, systemImage: kind.systemImage).labelStyle(.iconOnly).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(model.tool == .control && model.courseItemTool == kind ? Color(hexString: "#A626FF") : CP.ink)
                            .accessibilityLabel("Add \(kind.label)")
                            .help("Add \(kind.label)")
                        }
                        Button { importingImage = true } label: {
                            Label("Image", systemImage: "photo.badge.plus").labelStyle(.iconOnly).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(CP.ink)
                        .accessibilityLabel("Add image")
                        .help("Add image")
                    }
                    .padding(.vertical, CP.Space.xs)
                    Text("Text: tap the map. Rectangle/ellipse/line: drag on the map. Image: JPG/PNG max. 10 MB, 8000 px, 10 images per project. All objects can be dragged to move them.")
                        .font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
                        .padding(.bottom, CP.Space.xs)
                }
                if let item = model.selectedCourseItem {
                    group("Selected \(item.kind.label.lowercased())") {
                        CourseItemEditor(model: model, item: item)
                            .id(item.id)
                    }
                }
                group("Objects (\(items.count))") {
                    if items.isEmpty {
                        Text("No text, shapes, or images yet.").font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted).padding(.vertical, 8)
                    }
                    ForEach(items.reversed()) { it in
                        Button { model.selectedCourseItemID = it.id } label: {
                            HStack(spacing: CP.Space.m) {
                                Image(systemName: it.kind.systemImage).foregroundStyle(Color(hexString: it.colorHex ?? "#A626FF")).frame(width: 22)
                                Text(it.displayName.replacingOccurrences(of: "\n", with: " ")).font(.system(size: CP.fs(14))).foregroundStyle(CP.ink).lineLimit(1)
                                Spacer()
                                Text(Self.scopeLabel(it, in: set)).font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted).lineLimit(1)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(model.selectedCourseItemID == it.id ? Color(hexString: "#A626FF").opacity(0.1) : .clear)
                        .accessibilityLabel("\(it.kind.label) \(it.displayName)")
                        .help("\(it.kind.label) \(it.displayName)")
                    }
                }
            }
            .padding(CP.Space.l)
        }
    }

    /// "All courses" or the names of the courses the object appears on.
    static func scopeLabel(_ item: CourseItem, in set: CourseSet) -> String {
        guard let ids = item.scope else { return "All courses" }
        let names = ids.compactMap { set.course($0)?.name }
        return names.isEmpty ? "Not shown" : names.joined(separator: ", ")
    }

    // MARK: Report tab

    private var reportTab: some View {
        let loads = set.controlLoads().filter { $0.courseCount > 0 }.sorted { $0.visits > $1.visits }
        let legs = set.sharedLegLoads()
        let warnings = set.warnings()
        return ScrollView {
            // Lazy: control load rows not yet visible aren't created (60+ controls).
            LazyVStack(alignment: .leading, spacing: CP.Space.l) {
                reportTitle("Course summary")
                Grid(alignment: .leading, horizontalSpacing: CP.Space.m, verticalSpacing: CP.Space.xs) {
                    GridRow {
                        ForEach(["Course", "Length", "Climb", "Controls", "Competitors"], id: \.self) {
                            Text($0).font(.system(size: CP.fs(11), weight: .semibold)).foregroundStyle(CP.inkMuted)
                        }
                    }
                    ForEach(set.courses) { c in
                        GridRow {
                            Text(c.name).font(.system(size: CP.fs(13), weight: .medium)).lineLimit(1)
                            Text(verbatim: c.kind == .score ? "Score" : Fmt.km(set.length(of: c))).font(CP.mono(12))
                            Text(verbatim: c.climbM.map { "\($0) m" } ?? "–").font(CP.mono(12))
                            Text(verbatim: "\(set.controls(of: c).filter { $0.kind == .control }.count)").font(CP.mono(12))
                            Text(verbatim: "\(c.competitors)").font(CP.mono(12))
                        }
                    }
                }
                if set.courses.isEmpty { Text("No courses yet.").font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted) }

                reportTitle("Competitor load per control")
                if loads.isEmpty {
                    Text("Enter the number of competitors per course to calculate each control's load.").font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                } else {
                    let maxVisits = max(loads.first?.visits ?? 1, 1)
                    ForEach(loads, id: \.controlID) { l in
                        HStack(spacing: CP.Space.s) {
                            Text(verbatim: set.control(l.controlID)?.label(in: set) ?? "?").font(CP.mono(12, weight: .semibold)).frame(width: 34, alignment: .leading)
                            // Fixed bar width (no GeometryReader per row).
                            RoundedRectangle(cornerRadius: 3).fill(Color(hexString: "#A626FF").opacity(0.55))
                                .frame(width: max(2, 200 * Double(l.visits) / Double(maxVisits)), height: 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(verbatim: "\(l.visits)").font(CP.mono(12)).frame(width: 44, alignment: .trailing)
                            Text(verbatim: "\(l.courseCount)×").font(CP.mono(11)).foregroundStyle(CP.inkMuted).frame(width: 26, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Control \(set.control(l.controlID)?.label(in: set) ?? ""), \(l.visits) competitors, \(l.courseCount) courses")
                    }
                }

                if !legs.isEmpty {
                    reportTitle("Shared legs")
                    ForEach(legs, id: \.self) { l in
                        HStack {
                            Text(verbatim: "\(set.control(l.from)?.label(in: set) ?? "?")–\(set.control(l.to)?.label(in: set) ?? "?")").font(CP.mono(12, weight: .semibold))
                            Text("\(l.courseCount) courses").font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                            Spacer()
                            Text(verbatim: "\(l.visits) competitors").font(CP.mono(12))
                        }
                    }
                }

                reportTitle("Checks")
                if warnings.isEmpty {
                    Label("No issues", systemImage: "checkmark.circle").foregroundStyle(CP.sage.strong).font(.system(size: CP.fs(13)))
                } else {
                    VStack(alignment: .leading, spacing: CP.Space.xs) {
                        ForEach(warnings, id: \.self) { Text("• \($0)").font(.system(size: CP.fs(12))).foregroundStyle(CP.ink) }
                    }
                    .padding(CP.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CP.butter.fill, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                }

                Button { showingExport = true } label: {
                    Label("Export course…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(set.controls.isEmpty)
                Text("IOF XML 3.0 (MeOS, OE/SportSoftware, SI Config, Purple Pen, OCAD), course map PDF + descriptions, PNG + world file.")
                    .font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
            }
            .padding(CP.Space.l)
        }
    }

    private func reportTitle(_ s: String) -> some View {
        Text(s).font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
    }
}

// MARK: - Course name

/// Course name that can be typed directly; saved on Return, on focus change, or when the panel closes.
private struct CourseNameField: View {
    @ObservedObject var model: WorkspaceModel
    let course: Course
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: CP.Space.s) {
            Text("Name").foregroundStyle(CP.inkMuted)
            TextField("Course name (e.g. Men Elite)", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)
                .accessibilityIdentifier("courseName")
        }
        .font(.system(size: CP.fs(14)))
        .onAppear { name = course.name }
        .onChange(of: course.name) { _, v in if !focused { name = v } }
        .onChange(of: focused) { _, f in if !f { commit() } }
        .onDisappear(perform: commit)
    }

    private func commit() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = model.courseSet.course(course.id) else { return }
        if n.isEmpty { name = current.name; return }
        if n != current.name { model.updateCourse(course.id) { $0.name = n } }
    }
}

// MARK: - Description sheet (preview)

/// Description table as printed: column A (number), B (code), then IOF symbols C–H (or text);
/// thick line every 3 controls; finish as a full-width navigation row.
struct DescriptionSheetView: View {
    let sheet: DescriptionSheet
    var symbols = true
    /// Ink color (black or course purple), same as the printout.
    var ink: Color = CP.ink
    var onTapRow: (Int) -> Void = { _ in }

    var body: some View {
        let cell: CGFloat = 42
        VStack(spacing: 0) {
            if !sheet.title.isEmpty {
                Text(sheet.title).font(.system(size: CP.fs(14), weight: .semibold)).multilineTextAlignment(.center).lineLimit(2)
                    .minimumScaleFactor(0.7).padding(.horizontal, 6).frame(maxWidth: .infinity, alignment: .center).frame(height: cell)
                    .overlay(alignment: .bottom) { line(1) }
            }
            if !sheet.organizer.isEmpty {
                Text(sheet.organizer).font(.system(size: CP.fs(13))).multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 6).frame(maxWidth: .infinity, alignment: .center).frame(height: cell)
                    .overlay(alignment: .bottom) { line(1) }
            }
            HStack(spacing: 0) {
                Text(sheet.courseName).font(.system(size: CP.fs(14), weight: .semibold)).padding(.leading, 6).frame(maxWidth: .infinity, alignment: .leading)
                Text(sheet.lengthText).font(CP.mono(13)).frame(width: cell * 1.8).overlay(alignment: .leading) { vline() }
                Text(sheet.climbText).font(CP.mono(13)).frame(width: cell * 1.6).overlay(alignment: .leading) { vline() }
            }
            .frame(height: cell)
            .overlay(alignment: .bottom) { line(1) }
            let thickRows = Self.thickRows(sheet)
            ForEach(Array(sheet.rows.enumerated()), id: \.offset) { i, row in
                let thick = thickRows.contains(i)
                Button { onTapRow(i) } label: {
                    Group {
                        if symbols, row.kind == .finish {
                            FinishRowView(meters: row.finishMeters, color: ink)
                        } else {
                            HStack(spacing: 0) {
                                Group {
                                    switch row.kind {
                                    case .control: Text(row.number).font(.system(size: CP.fs(17), weight: .medium))
                                    default: ControlGlyph(kind: row.kind, color: ink).frame(width: 24, height: 24)
                                    }
                                }
                                .frame(maxWidth: symbols ? .infinity : cell, maxHeight: .infinity)
                                Text(row.code).font(.system(size: CP.fs(17), weight: .medium)).frame(maxWidth: symbols ? .infinity : cell, maxHeight: .infinity)
                                    .overlay(alignment: .leading) { vline() }
                                if symbols {
                                    symbolCells(row)
                                } else {
                                    Text(row.text).font(.system(size: CP.fs(13))).lineLimit(2).minimumScaleFactor(0.8)
                                        .padding(.horizontal, 6)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                        .overlay(alignment: .leading) { vline() }
                                }
                            }
                        }
                    }
                    .frame(height: cell)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { if i < sheet.rows.count - 1 { line(thick ? 2.5 : 1) } }
                .accessibilityLabel("Row \(row.number) \(row.code) \(row.text)")
                .help("Row \(row.number) \(row.code) \(row.text)")
            }
        }
        .foregroundStyle(ink)
        .background(Color.white.opacity(0.0001))
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 2.5))
    }

    /// Columns C–H; thick lines after C and F like the IOF sheet.
    @ViewBuilder private func symbolCells(_ row: DescriptionSheet.Row) -> some View {
        let d = row.description
        let cols: [[IOFPictogram.Shape]?] = [IOFPictogram.shapes(d.which), IOFPictogram.shapes(d.feature), IOFPictogram.shapes(d.appearance),
                                             IOFPictogram.dimensionShapes(d.dimension), IOFPictogram.shapes(d.location), IOFPictogram.shapes(d.other)]
        ForEach(0..<6, id: \.self) { k in
            ZStack {
                // Unfilled columns are left empty.
                if let shapes = cols[k] { IOFSymbolView(shapes: shapes, color: ink).padding(5) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) { vline(k == 1 || k == 4 ? 2 : 1) }
        }
    }

    /// The row after every 3rd, 6th, 9th, … control gets a thick line.
    static func thickRows(_ sheet: DescriptionSheet) -> Set<Int> {
        var n = 0, out = Set<Int>()
        for (i, r) in sheet.rows.enumerated() where r.kind == .control {
            n += 1
            if n % 3 == 0, i < sheet.rows.count - 1 { out.insert(i) }
        }
        return out
    }

    private func line(_ w: CGFloat) -> some View { Rectangle().fill(ink).frame(height: w) }
    private func vline(_ w: CGFloat = 1) -> some View { Rectangle().fill(ink).frame(width: w) }
}

/// One IOF description symbol (shape from CakraCore, same as the PDF output).
struct IOFSymbolView: View {
    let shapes: [IOFPictogram.Shape]
    var color: Color = Color(uiColor: .label)

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            ctx.withCGContext { cg in
                IOFPictogram.draw(shapes, in: cg, rect: rect, flipped: true, color: UIColor(color).cgColor)
            }
            for case let .text(str, at, rel) in shapes {
                ctx.draw(Text(str).font(.system(size: rel * side, weight: .medium)).foregroundStyle(color),
                         at: CGPoint(x: rect.minX + at.x * side, y: rect.maxY - at.y * side))
            }
        }
        .accessibilityHidden(true)
    }

    /// Icon for the symbol picker menu.
    @MainActor static func image(_ id: String) -> Image? {
        if let img = cache[id] { return Image(uiImage: img) }
        guard let shapes = IOFPictogram.shapes(id) else { return nil }
        let size = CGSize(width: 26, height: 26)
        let img = UIGraphicsImageRenderer(size: size).image { r in
            IOFPictogram.draw(shapes, in: r.cgContext, rect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2),
                              flipped: true, color: UIColor.black.cgColor)
        }.withRenderingMode(.alwaysTemplate)
        cache[id] = img
        return Image(uiImage: img)
    }

    @MainActor private static var cache: [String: UIImage] = [:]
}

/// IOF finish row: circle — distance — arrow to the double finish circle.
private struct FinishRowView: View {
    let meters: Int?
    var color: Color = Color(uiColor: .label)

    var body: some View {
        Canvas { ctx, size in
            let cy = size.height / 2, r = size.height * 0.26
            let left = size.height * 0.55, right = size.width - size.height * 0.55
            let ink = GraphicsContext.Shading.color(color)
            func circle(_ x: CGFloat, _ rr: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - rr, y: cy - rr, width: 2 * rr, height: 2 * rr)) }
            ctx.stroke(circle(left, r), with: ink, lineWidth: 1.6)
            ctx.stroke(circle(right, r), with: ink, lineWidth: 1.6)
            ctx.stroke(circle(right, r * 0.62), with: ink, lineWidth: 1.6)
            let label = meters.map { "\($0) m" } ?? ""
            let gap: CGFloat = label.isEmpty ? 0 : 34
            let mid = size.width / 2
            var dash = Path()
            dash.move(to: CGPoint(x: left + r, y: cy)); dash.addLine(to: CGPoint(x: mid - gap, y: cy))
            dash.move(to: CGPoint(x: mid + gap, y: cy)); dash.addLine(to: CGPoint(x: right - r - 4, y: cy))
            ctx.stroke(dash, with: ink, style: StrokeStyle(lineWidth: 1.4, dash: [12, 7]))
            var head = Path()
            let tip = right - r
            head.move(to: CGPoint(x: tip - 9, y: cy - 7)); head.addLine(to: CGPoint(x: tip, y: cy)); head.addLine(to: CGPoint(x: tip - 9, y: cy + 7))
            ctx.stroke(head, with: ink, lineWidth: 1.6)
            if !label.isEmpty { ctx.draw(Text(label).font(CP.mono(13)).foregroundStyle(color), at: CGPoint(x: mid, y: cy)) }
        }
        .accessibilityHidden(true)
    }
}

/// Icons for start (triangle), control (circle), finish (double circle) in course purple.
struct ControlGlyph: View {
    let kind: ControlKind
    var color = Color(hexString: "#A626FF")
    var body: some View {
        let purple = color
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - 1.5
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            switch kind {
            case .control:
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(purple), lineWidth: 1.6)
            case .finish:
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(purple), lineWidth: 1.4)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.6, width: 1.2 * r, height: 1.2 * r)), with: .color(purple), lineWidth: 1.4)
            case .start:
                var p = Path()
                for i in 0..<3 {
                    let a = -Double.pi / 2 + Double(i) * 2 * .pi / 3
                    let q = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a) + r * 0.15)
                    if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
                p.closeSubpath()
                ctx.stroke(p, with: .color(purple), lineWidth: 1.6)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Control editor (code + IOF description)

private struct ControlEditor: View {
    @ObservedObject var model: WorkspaceModel
    let controlID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var codeText = ""
    @State private var dimension = ""

    private var control: ControlPoint? { model.courseSet.control(controlID) }

    var body: some View {
        NavigationStack {
            Form {
                if let c = control {
                    Section {
                        HStack {
                            ControlGlyph(kind: c.kind).frame(width: 22, height: 22)
                            Text(c.kind.label).font(.system(size: CP.fs(15), weight: .semibold))
                            Spacer()
                            Text(verbatim: c.label(in: model.courseSet)).font(CP.mono(17, weight: .semibold))
                        }
                        if c.kind == .control {
                            HStack {
                                Text("Code")
                                Spacer()
                                TextField("31–255", text: $codeText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                    .onSubmit { applyCode() }
                                Button("Use") { applyCode() }.buttonStyle(.bordered)
                            }
                        }
                        let using = model.courseSet.courses.filter { $0.controlIDs.contains(c.id) }.map(\.name)
                        Text(using.isEmpty ? "Not used by any course yet." : "Used by: \(using.joined(separator: ", "))")
                            .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    }
                    Section {
                        Stepper(value: Binding(get: { c.effectiveSize }, set: { model.setControlSize($0, for: controlID) }),
                                in: ControlPoint.sizeRange, step: 0.1) {
                            HStack {
                                Text("Object size")
                                Spacer()
                                Text(verbatim: "\(Int((c.effectiveSize * 100).rounded()))%").font(CP.mono(15))
                            }
                        }
                        .accessibilityLabel("Control object size, \(Int((c.effectiveSize * 100).rounded())) percent")
                        if c.sizeFactor != nil {
                            Button { model.setControlSize(1, for: controlID) } label: { Label("IOF standard (100%)", systemImage: "arrow.counterclockwise") }
                        }
                    } header: { Text("Size") } footer: {
                        Text("100% = IOF standard size for this scale. Size of all controls at once: Controls tab → Course symbol size.")
                    }
                    Section {
                        Text(c.description.isEmpty ? "No description yet." : c.description.text)
                            .font(.system(size: CP.fs(15), weight: .medium))
                    } header: { Text("Description (IOF text)") }
                    Section {
                        picker(.d, value: c.description.feature) { v in model.updateControl(controlID) { $0.description.feature = v } }
                        picker(.c, value: c.description.which) { v in model.updateControl(controlID) { $0.description.which = v } }
                        picker(.e, value: c.description.appearance) { v in model.updateControl(controlID) { $0.description.appearance = v } }
                        HStack {
                            Text("F · Dimensions")
                            Spacer()
                            TextField("e.g. 1.5 or 8x4", text: $dimension)
                                .multilineTextAlignment(.trailing)
                                .onSubmit { model.updateControl(controlID) { $0.description.dimension = dimension.isEmpty ? nil : dimension } }
                        }
                        picker(.f, value: IOFSymbols.symbol(c.description.dimension)?.column == .f ? c.description.dimension : nil, title: "F · Combination") { v in
                            dimension = ""
                            model.updateControl(controlID) { $0.description.dimension = v }
                        }
                        picker(.g, value: c.description.location) { v in model.updateControl(controlID) { $0.description.location = v } }
                        picker(.h, value: c.description.other) { v in model.updateControl(controlID) { $0.description.other = v } }
                    } header: { Text("Columns C–H") }
                    Section {
                        Button(role: .destructive) {
                            model.deleteControl(controlID)
                            dismiss()
                        } label: { Label("Delete from map and all courses", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let c = control, IOFSymbols.symbol(c.description.dimension)?.column != .f, dimension != (c.description.dimension ?? "") {
                            model.updateControl(controlID) { $0.description.dimension = dimension.isEmpty ? nil : dimension }
                        }
                        applyCode()
                        dismiss()
                    }
                }
            }
            .onAppear {
                codeText = control?.code.map(String.init) ?? ""
                let d = control?.description.dimension
                dimension = IOFSymbols.symbol(d)?.column == .f ? "" : (d ?? "")
            }
        }
    }

    private func applyCode() {
        guard let c = control, c.kind == .control, let code = Int(codeText), code != c.code else { return }
        model.setCode(code, for: controlID)
        codeText = model.courseSet.control(controlID)?.code.map(String.init) ?? codeText
    }

    /// Picks one column's symbol; column D is grouped as in the IOF specification.
    private func picker(_ column: IOFSymbol.Column, value: String?, title: String? = nil, set: @escaping (String?) -> Void) -> some View {
        let symbols = IOFSymbols.symbols(in: column)
        let groups = Array(NSOrderedSet(array: symbols.map { $0.group ?? "" })) as? [String] ?? [""]
        return Picker("\(column.rawValue) · \(title.map { String($0.dropFirst(4)) } ?? column.title)",
                      selection: Binding(get: { value ?? "" }, set: { set($0.isEmpty ? nil : $0) })) {
            Text("—").tag("")
            ForEach(groups, id: \.self) { g in
                Section(g) {
                    ForEach(symbols.filter { ($0.group ?? "") == g }) { s in
                        Label {
                            Text("\(s.id)  \(s.name)")
                        } icon: {
                            IOFSymbolView.image(s.id) ?? Image(systemName: "questionmark.square.dashed")
                        }
                        .tag(s.id)
                    }
                }
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Selected control size (status bar)

/// − 100% + for the selected control; tap the percentage = back to the IOF standard.
private struct ControlSizeStepper: View {
    @ObservedObject var model: WorkspaceModel
    let control: ControlPoint

    var body: some View {
        HStack(spacing: CP.Space.xs) {
            ControlGlyph(kind: control.kind).frame(width: 16, height: 16)
            Text(verbatim: control.label(in: model.courseSet)).font(CP.mono(12, weight: .semibold))
            Button { model.stepControlSize(-0.1, for: control.id) } label: { Image(systemName: "minus") }
                .buttonStyle(.bordered)
                .disabled(control.effectiveSize <= ControlPoint.sizeRange.lowerBound + 0.001)
                .accessibilityLabel("Shrink control")
                .help("Shrink control")
            Button { model.setControlSize(1, for: control.id) } label: {
                Text(verbatim: "\(Int((control.effectiveSize * 100).rounded()))%").font(CP.mono(12)).frame(minWidth: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Control size \(Int((control.effectiveSize * 100).rounded())) percent, tap for IOF standard")
            .help("Control size \(Int((control.effectiveSize * 100).rounded())) percent, tap for IOF standard")
            Button { model.stepControlSize(0.1, for: control.id) } label: { Image(systemName: "plus") }
                .buttonStyle(.bordered)
                .disabled(control.effectiveSize >= ControlPoint.sizeRange.upperBound - 0.001)
                .accessibilityLabel("Enlarge control")
                .help("Enlarge control")
        }
        .tint(CP.ink)
    }
}

// MARK: - PDF preview (same as the export)

struct CoursePreviewSheet: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var courseID: UUID?
    @State private var page = 0
    @State private var data: Data?
    @State private var share: ExportSheet.ShareItems?

    private var hasSeparatePage: Bool {
        let l = model.courseSet.effectivePrintLayout
        return l.separateDescriptionPage || !l.descriptionOnMap
    }

    /// The "All controls" option in the course menu.
    private static let allControlsID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// nil = "All controls" (master).
    private var course: Course? {
        let id = courseID ?? model.selectedCourseID
        return id == Self.allControlsID ? nil : id.flatMap { model.courseSet.course($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: CP.Space.m) {
                HStack(spacing: CP.Space.m) {
                    Picker("Course", selection: Binding(get: { course?.id ?? Self.allControlsID }, set: { courseID = $0 })) {
                        Text("All controls").tag(Self.allControlsID)
                        ForEach(model.courseSet.courses) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    if hasSeparatePage {
                        Picker("Page", selection: $page) {
                            Text("Competition map").tag(0)
                            Text("Separate descriptions").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                    }
                }
                .padding(.horizontal, CP.Space.l)
                if let data {
                    PDFPreview(data: data, page: page)
                        .accessibilityLabel(page == 1 ? "Preview control description page" : "Preview competition map")
                } else {
                    ProgressView("Preparing PDF…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text("Exactly what the exported PDF contains: \(model.project.sheet.paper.name) map at 1:\(model.project.sheet.scaleDenominator) with overprint, control descriptions, and course text, shapes, and images\(hasSeparatePage ? ", plus a separate description page" : ""). Pinch to zoom.")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    .padding(.horizontal, CP.Space.l)
                    .padding(.bottom, CP.Space.s)
            }
            .padding(.top, CP.Space.s)
            .background(CP.paper2)
            .navigationTitle("Preview \(course?.name ?? "All controls")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export PDF") { exportPDF() }.disabled(data == nil)
                }
            }
            .task(id: course?.id ?? Self.allControlsID) { await render() }
            .sheet(item: $share) { ActivityView(items: $0.urls) }
        }
    }

    private func render() async {
        data = nil
        guard let req = model.coursePDFRequest(for: course) else { return }
        data = await Task.detached(priority: .userInitiated) { GeoPDFExporter.document(req) }.value
    }

    private func exportPDF() {
        guard let data else { return }
        let dir = TempExports.newDirectory()
        let url = dir.appendingPathComponent("\(safeFileName(model.project.name))_\(safeFileName(course?.name ?? "All controls")).pdf")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
            share = ExportSheet.ShareItems(urls: [url])
        } catch {
            model.notice = "Couldn't write PDF: \(error.localizedDescription)"
        }
    }
}

/// PDFKit: shows one page (pinch to zoom).
private struct PDFPreview: UIViewRepresentable {
    let data: Data
    let page: Int

    final class Coordinator {
        var data: Data?
        var page = -1
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePage  // one whole page visible, like a printed sheet
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(white: 0.9, alpha: 1)
        v.pageShadowsEnabled = true
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if context.coordinator.data != data {
            context.coordinator.data = data
            v.document = PDFDocument(data: data)
        }
        guard let doc = v.document, let p = doc.page(at: min(page, doc.pageCount - 1)), context.coordinator.page != page || v.currentPage != p else { return }
        context.coordinator.page = page
        DispatchQueue.main.async {
            if page == 1 {
                // Description page: zoom in on the table (top-left of the A4) so it's readable; pinch to zoom again.
                v.autoScales = false
                let box = p.bounds(for: .mediaBox)
                v.scaleFactor = max(v.bounds.width, 300) / 260
                v.go(to: CGRect(x: 0, y: box.height - 300, width: 260, height: 300), on: p)
            } else {
                v.autoScales = true
                v.go(to: p)
            }
        }
    }
}

// MARK: - Print layout

/// One-page competition map settings: description position + size, title, north arrow, scale bar.
private struct PrintLayoutSection: View {
    @ObservedObject var model: WorkspaceModel
    let sheet: DescriptionSheet

    var body: some View {
        let l = model.courseSet.effectivePrintLayout
        VStack(alignment: .leading, spacing: CP.Space.s) {
            Text("Print layout").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
            Toggle("Descriptions on map", isOn: Binding(get: { l.descriptionOnMap }, set: { v in model.updatePrintLayout { $0.descriptionOnMap = v } }))
            Picker("Description style", selection: Binding(get: { l.descriptionSymbols }, set: { v in model.updatePrintLayout { $0.descriptionSymbols = v } })) {
                Text("IOF symbols").tag(true)
                Text("Text").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("descriptionStyle")
            Picker("Description color", selection: Binding(get: { l.descriptionColor }, set: { v in model.updatePrintLayout { $0.descriptionColor = v } })) {
                ForEach(CoursePrintLayout.DescriptionColor.allCases, id: \.self) { c in
                    Text(c == .black ? "Black" : "Purple (like controls)").tag(c)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("descriptionColor")
            if l.descriptionOnMap {
                Stepper(value: Binding(get: { l.descriptionCellMM }, set: { v in model.updatePrintLayout { $0.descriptionCellMM = v } }),
                        in: CoursePrintLayout.cellRangeMM, step: 0.5) {
                    HStack {
                        Text("Description box size")
                        Spacer()
                        Text(verbatim: Fmt.mm(l.descriptionCellMM, decimals: 1)).font(CP.mono(13))
                    }
                }
                // Overflow rows move to the next column.
                Toggle("Limit rows per column", isOn: Binding(get: { l.descriptionMaxRows != nil },
                                                              set: { v in model.updatePrintLayout { $0.descriptionMaxRows = v ? 8 : nil } }))
                if let rows = l.descriptionMaxRows {
                    Stepper(value: Binding(get: { rows }, set: { v in model.updatePrintLayout { $0.descriptionMaxRows = v } }),
                            in: CoursePrintLayout.maxRowsRange) {
                        HStack {
                            Text("Max rows")
                            Spacer()
                            Text(verbatim: "\(rows) rows · \(sheet.columns(maxRows: rows).count) columns").font(CP.mono(13))
                        }
                    }
                    .accessibilityLabel("Max rows per column")
                    .accessibilityValue("\(rows)")
                }
                DescriptionPositionEditor(model: model, sheet: sheet, layout: l)
            }
            Toggle("Separate description page", isOn: Binding(get: { l.separateDescriptionPage || !l.descriptionOnMap },
                                                             set: { v in model.updatePrintLayout { $0.separateDescriptionPage = v } }))
                .disabled(!l.descriptionOnMap)
            Text("IOF: description boxes 5–7 mm. Descriptions have a white background on the map.")
                .font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
        }
        .font(.system(size: CP.fs(14)))
        .tint(CP.sage.strong)
    }
}

/// Description position: drag the purple box in the map area thumbnail, or pick a corner.
private struct DescriptionPositionEditor: View {
    @ObservedObject var model: WorkspaceModel
    let sheet: DescriptionSheet
    let layout: CoursePrintLayout
    @State private var drag: CGSize = .zero

    var body: some View {
        let spec = model.project.sheet
        let block = GeoPDFExporter.descriptionBlockSizeMM(sheet, layout: layout)
        let origin = GeoPDFExporter.descriptionOriginMM(block: block, layout: layout, sheet: spec)
        let width: CGFloat = 340
        let k = width / spec.mappingWidthMM
        let height = spec.mappingHeightMM * k
        let columns = sheet.columns(maxRows: layout.descriptionMaxRows).count
        VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack {
                Text("Description position")
                Spacer()
                Text(layout.descriptionOffsetMM == nil ? layout.descriptionCorner.label
                     : "\(Int(origin.x.rounded())) × \(Int(origin.y.rounded())) mm")
                    .font(CP.mono(12)).foregroundStyle(CP.inkMuted)
                    .accessibilityIdentifier("descriptionPosition")
            }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.white).overlay(Rectangle().strokeBorder(CP.line))
                ZStack {
                    Rectangle().fill(Color(hexString: "#A626FF").opacity(0.18))
                    Rectangle().strokeBorder(Color(hexString: "#A626FF"), lineWidth: 1.5)
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { i in
                            if i > 0 { Rectangle().fill(Color(hexString: "#A626FF")).frame(width: 1) }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(width: block.w * k, height: block.h * k)
                .offset(x: origin.x * k + drag.width, y: origin.y * k + drag.height)
                .gesture(DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { v in
                        let x = ((origin.x + v.translation.width / k)).rounded()
                        let y = ((origin.y + v.translation.height / k)).rounded()
                        drag = .zero
                        model.updatePrintLayout { $0.descriptionOffsetMM = Point2D(x: max(0, x), y: max(0, y)) }
                    })
                .accessibilityLabel("Description box, drag to move")
            }
            .frame(width: width, height: height)
            .clipped()
            HStack(spacing: CP.Space.xs) {
                ForEach(CoursePrintLayout.Corner.allCases, id: \.self) { c in
                    Button(c.label) {
                        model.updatePrintLayout { $0.descriptionCorner = c; $0.descriptionOffsetMM = nil }
                    }
                    .font(.system(size: CP.fs(12)))
                    .buttonStyle(.bordered)
                    .tint(layout.descriptionOffsetMM == nil && layout.descriptionCorner == c ? Color(hexString: "#A626FF") : CP.inkMuted)
                }
            }
            Text("Drag the purple box to place it freely, or pick a corner. The thumbnail is proportional to the map area.")
                .font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
        }
    }
}

/// Editor for the selected course object: text content, size, fill, image width, courses, delete.
private struct CourseItemEditor: View {
    @ObservedObject var model: WorkspaceModel
    let item: CourseItem
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            switch item.kind {
            case .text:
                TextField("Text (e.g. place name, post number)", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($editing)
                    .onSubmit(commit)
                    .onChange(of: editing) { _, now in if !now { commit() } }
                    .accessibilityIdentifier("courseItemText")
                Stepper(value: Binding(get: { item.effectiveTextHeightMM },
                                       set: { v in model.updateCourseItem(item.id) { $0.textHeightMM = v } }),
                        in: CourseItem.textHeightRangeMM, step: 0.5) {
                    HStack {
                        Text("Font size")
                        Spacer()
                        Text(verbatim: "\(Fmt.mm(item.effectiveTextHeightMM, decimals: 1)) · \(Int(CourseItem.points(forTextHeightMM: item.effectiveTextHeightMM).rounded())) pt")
                            .font(CP.mono(13))
                    }
                }
                .accessibilityLabel("Font size")
                .accessibilityValue(Fmt.mm(item.effectiveTextHeightMM, decimals: 1))
                HStack(spacing: CP.Space.s) {
                    Text("Style")
                    Spacer()
                    Picker("Weight", selection: Binding(get: { item.bold == true },
                                                          set: { v in model.updateCourseItem(item.id) { $0.bold = v ? true : nil } })) {
                        Text("Normal").tag(false)
                        Text("Bold").fontWeight(.bold).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .accessibilityIdentifier("courseTextWeight")
                    Toggle(isOn: Binding(get: { item.italic == true },
                                         set: { v in model.updateCourseItem(item.id) { $0.italic = v ? true : nil } })) {
                        Image(systemName: "italic")
                    }
                    .toggleStyle(.button)
                    .accessibilityLabel("Italic")
                    .help("Italic")
                    .accessibilityIdentifier("courseTextItalic")
                }
            case .rectangle, .ellipse:
                Toggle("Transparent fill (e.g. out-of-bounds area)", isOn: Binding(get: { item.isFilled },
                                                                                 set: { v in model.updateCourseItem(item.id) { $0.filled = v ? true : nil } }))
            case .image:
                Stepper(value: Binding(get: { item.widthMM ?? CourseItem.defaultImageWidthMM },
                                       set: { v in model.updateCourseItem(item.id) { $0.widthMM = v } }),
                        in: CourseItem.imageWidthRangeMM, step: 5) {
                    HStack { Text("Width on paper"); Spacer(); Text(verbatim: Fmt.mm(item.widthMM ?? CourseItem.defaultImageWidthMM, decimals: 0)).font(CP.mono(13)) }
                }
                .accessibilityIdentifier("courseImageWidth")
            case .line:
                EmptyView()
            }
            if item.kind != .image {
                CourseItemColorRow(model: model, item: item)
            }
            CourseItemScopeRow(model: model, item: item)
            Button(role: .destructive) { model.deleteCourseItem(item.id) } label: {
                Label("Delete \(item.kind.label.lowercased())", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteCourseItem")
        }
        .font(.system(size: CP.fs(14)))
        .tint(CP.sage.strong)
        .padding(.vertical, CP.Space.xs)
        .onAppear {
            // New text (default placeholder content): empty field, ready for typing right away.
            if item.kind == .text, item.text == CourseItem.placeholderText {
                text = ""
                editing = true
            } else {
                text = item.text ?? ""
            }
        }
        // Selecting another object / switching tabs before the keyboard closes: text is still saved.
        .onDisappear(perform: commit)
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != (item.text ?? "") else { return }
        if t.isEmpty { text = item.text ?? ""; return }
        model.updateCourseItem(item.id) { $0.text = t }
    }
}

/// Object color: quick colors + a free color picker. Color picker changes are coalesced (short delay)
/// so one drag = one undo step.
private struct CourseItemColorRow: View {
    @ObservedObject var model: WorkspaceModel
    let item: CourseItem
    @State private var picked: Color = .clear
    @State private var pending: Task<Void, Never>?

    private var current: String { item.colorHex ?? CourseStyle.isom.colorHex }

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.xs) {
            Text("Color")
            HStack(spacing: 8) {
                ForEach(CourseItem.swatches, id: \.self) { hex in
                    Button { apply(hex) } label: {
                        Circle().fill(Color(hexString: hex))
                            .overlay(Circle().strokeBorder(CP.line))
                            .overlay(Circle().strokeBorder(CP.ink, lineWidth: current.uppercased() == hex ? 2.5 : 0).padding(-3))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(hex)")
                    .help("Color \(hex)")
                }
                Spacer(minLength: 0)
                ColorPicker("Other color", selection: Binding(get: { picked }, set: { c in
                    picked = c
                    let hex = UIColor(c).hexString
                    pending?.cancel()
                    pending = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        if !Task.isCancelled { apply(hex) }
                    }
                }), supportsOpacity: false)
                .labelsHidden()
                .accessibilityIdentifier("courseItemColor")
            }
        }
        .onAppear { picked = Color(hexString: current) }
        .onChange(of: item.colorHex) { _, _ in picked = Color(hexString: current) }
    }

    private func apply(_ hex: String) {
        let v = hex.uppercased() == CourseStyle.isom.colorHex.uppercased() ? nil : hex.uppercased()
        guard v != item.colorHex else { return }
        model.updateCourseItem(item.id) { $0.colorHex = v }
    }
}

/// Courses the object appears on: all courses, or a chosen set of courses.
private struct CourseItemScopeRow: View {
    @ObservedObject var model: WorkspaceModel
    let item: CourseItem

    var body: some View {
        let courses = model.courseSet.courses
        let scope = item.scope
        VStack(alignment: .leading, spacing: CP.Space.xs) {
            Toggle("Show on all courses", isOn: Binding(get: { scope == nil }, set: { all in
                model.updateCourseItem(item.id) { i in
                    // Turning off "all": start from the currently open course (or the first course).
                    i.setScope(all ? nil : [model.selectedCourseID ?? courses.first?.id].compactMap { $0 })
                }
            }))
            .disabled(courses.isEmpty)
            .accessibilityIdentifier("courseItemAllCourses")
            if let scope {
                ForEach(courses) { c in
                    let on = scope.contains(c.id)
                    Button {
                        model.updateCourseItem(item.id) { i in
                            var ids = i.scope ?? []
                            if on { ids.removeAll { $0 == c.id } } else { ids.append(c.id) }
                            // At least one course; all checked = all courses.
                            guard !ids.isEmpty else { return }
                            i.setScope(Set(ids) == Set(courses.map(\.id)) ? nil : ids)
                        }
                    } label: {
                        HStack {
                            Image(systemName: on ? "checkmark.square.fill" : "square")
                                .foregroundStyle(on ? Color(hexString: "#A626FF") : CP.inkMuted)
                            Text("Course \(c.name)").foregroundStyle(CP.ink)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, CP.Space.s)
                    .accessibilityLabel("Show on course \(c.name)")
                    .help("Show on course \(c.name)")
                    .accessibilityValue(on ? "selected" : "not selected")
                }
            }
        }
    }
}

// MARK: - Lightweight rows (Equatable: redrawn only when their content changes)

private struct CourseCardView: View, Equatable {
    let name: String
    let subtitle: String
    let selected: Bool
    let isCourse: Bool
    /// None of the course's controls is in the locked map area.
    var outsideMap = false
    let onTap: () -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.name == b.name && a.subtitle == b.subtitle && a.selected == b.selected && a.isCourse == b.isCourse && a.outsideMap == b.outsideMap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: CP.Space.s) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color(hexString: "#A626FF") : CP.inkMuted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                    Text(subtitle).font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    if outsideMap {
                        Label("Outside the map area", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: CP.fs(12), weight: .medium))
                            .foregroundStyle(CP.rose.strong)
                            .accessibilityIdentifier("courseOutsideMap")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCourse ? "Course \(name)" : name)
        .help(isCourse ? "Course \(name)" : name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ControlRowView: View, Equatable {
    let control: ControlPoint
    let label: String
    let number: String
    let detail: String?
    let selected: Bool
    let onTap: () -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.control == b.control && a.label == b.label && a.number == b.number && a.detail == b.detail && a.selected == b.selected
    }

    var body: some View {
        let c = control
        Button(action: onTap) {
            HStack(spacing: CP.Space.s) {
                ControlGlyph(kind: c.kind).frame(width: 18, height: 18)
                Text(verbatim: number).font(CP.mono(12)).foregroundStyle(CP.inkMuted).frame(width: 18, alignment: .trailing)
                Text(verbatim: label).font(CP.mono(14, weight: .semibold)).foregroundStyle(CP.ink).frame(width: 36, alignment: .leading)
                Text(c.description.isEmpty ? (c.kind == .control ? "tap for description" : c.kind.label) : c.description.text)
                    .font(.system(size: CP.fs(13))).foregroundStyle(c.description.isEmpty ? CP.inkMuted : CP.ink).lineLimit(1)
                Spacer(minLength: 2)
                if let detail { Text(verbatim: detail).font(CP.mono(11)).foregroundStyle(CP.inkMuted) }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 4)
            .background(selected ? CP.sky.fill : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(c.kind.label) \(label)\(number.isEmpty ? "" : ", number \(number)")")
        .help("\(c.kind.label) \(label)\(number.isEmpty ? "" : ", number \(number)")")
    }
}
