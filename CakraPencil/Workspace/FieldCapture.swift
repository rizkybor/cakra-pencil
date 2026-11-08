import CakraCore
import PhotosUI
import SwiftUI
import UIKit

/// Field capture on iPad (top of the Field panel): record a track, add a note with photos, average a position.
/// Not shown on Mac (no GPS / field camera); the Mac reviews the same data.
struct FieldCaptureSection: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var recorder: FieldRecorder
    @State private var addingNote = false
    @State private var averagingOpen = false
    @State private var readyCheck = false
    @State private var vegetationOpen = false

    static var isAvailable: Bool { !ProcessInfo.processInfo.isMacCatalystApp }

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack(alignment: .center, spacing: CP.Space.s) {
                gpsStatus
                Spacer(minLength: 0)
                if DeviceCapabilities.canRecordTracks, !recorder.isRecording { modeMenu }
            }
            if let hint = Self.gpsText(recorder).hint {
                Text(hint)
                    .font(.system(size: CP.fs(11)))
                    .foregroundStyle(CP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if recorder.isRecording { recordingCard }
            // Icon buttons in one row: record track, add note, average position (names in tooltips / VoiceOver).
            HStack(spacing: CP.Space.s) {
                // Track recording: iPad Wi-Fi + Cellular only (GPS chip); not shown on Wi-Fi-only iPads.
                if DeviceCapabilities.canRecordTracks, !recorder.isRecording {
                    iconButton("record.circle", "Record track", tone: CP.rose, id: "fieldRecord") { model.startTrackRecording() }
                        .disabled(model.zone == nil)
                }
                iconButton("mappin.and.ellipse", "Add note", tone: CP.sage, id: "fieldAddNote") { addingNote = true }
                iconButton("scope", "Average position", tone: CP.sky, id: "fieldAverage") { averagingOpen = true }
                iconButton("leaf", "Vegetation", tone: CP.butter, id: "fieldVegetation") { vegetationOpen = true }
            }
            HStack(spacing: CP.Space.s) {
                secondaryButton("checklist", "Ready check", id: "fieldReadyCheck") { readyCheck = true }
                secondaryButton("rectangle.inset.filled.and.person.filled", "Field mode", id: "fieldModeEnter") { model.enterFieldMode() }
            }
        }
        .padding(CP.Space.m)
        .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(CP.line))
        .sheet(isPresented: $addingNote) { NewFieldNoteSheet(model: model, recorder: recorder) }
        .sheet(isPresented: $readyCheck) { ReadyCheckSheet(model: model) }
        .sheet(isPresented: $averagingOpen) { AveragingSheet(model: model, recorder: recorder) }
        .sheet(isPresented: $vegetationOpen) { VegetationSheet(model: model, recorder: recorder) }
    }

    private func secondaryButton(_ icon: String, _ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: CP.fs(13), weight: .medium))
                .foregroundStyle(CP.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func iconButton(_ icon: String, _ name: String, tone: CP.Tone, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: CP.fs(19), weight: .semibold))
        }
        .buttonStyle(FieldButtonStyle(tone: tone))
        .accessibilityLabel(name)
        .accessibilityIdentifier(id)
        .help(name)
    }

    /// Recording detail (battery saver / normal / detailed) as a small capsule menu.
    private var modeMenu: some View {
        Menu {
            Picker("Recording detail", selection: $recorder.mode) {
                ForEach(FieldRecorder.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: recorder.mode == .saver ? "battery.75percent" : recorder.mode == .detail ? "point.3.filled.connected.trianglepath.dotted" : "figure.walk")
                Text(recorder.mode.rawValue)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: CP.fs(12), weight: .medium))
            .foregroundStyle(CP.ink)
            .padding(.horizontal, 10).frame(height: 28)
            .background(CP.paper2, in: Capsule())
            .overlay(Capsule().strokeBorder(CP.line))
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Recording detail: \(recorder.mode.rawValue)")
        .accessibilityIdentifier("fieldRecordMode")
    }

    private var gpsStatus: some View {
        HStack(spacing: 6) {
            let status = Self.gpsText(recorder)
            Circle().fill(status.good ? CP.sage.strong : CP.peach.strong).frame(width: 8, height: 8)
            Text(status.title).font(.system(size: CP.fs(13), weight: .medium)).foregroundStyle(status.good ? CP.ink : CP.peach.strong)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fieldGPSStatus")
    }

    /// Short status for the header, an optional longer hint below it, and whether the fix is good.
    static func gpsText(_ r: FieldRecorder) -> (title: String, hint: String?, good: Bool) {
        switch r.authorization {
        case .denied, .restricted:
            return ("Location off", "Turn on Location Services for OCCA in Settings › Privacy & Security.", false)
        default: break
        }
        guard let f = r.lastFix, r.hasFix else {
            return ("Waiting for GPS", DeviceCapabilities.canRecordTracks
                    ? "Starts when you record, add a note or average."
                    : "This iPad has no GPS chip (Wi-Fi only), so track recording is not available. Notes can be placed at the map center; an external GNSS receiver (Bluetooth) gives GPS positions for notes and averaging.", false)
        }
        let a = f.horizontalAccuracy
        let source = r.isExternalGNSS ? "External GNSS" : "GPS"
        // Wi-Fi positioning (no GPS chip) is ±50 m or worse; track points worse than ±30 m are not recorded.
        if a > 30 {
            return ("\(source) ±\(Int(a.rounded())) m", "Too coarse for fieldwork (over ±30 m) — wait for a better fix or move to open sky.", false)
        }
        return ("\(source) ±\(Int(a.rounded())) m", a > 15 ? "Weak signal — wait a moment or move to open sky." : nil, a <= 15)
    }

    /// One-line description (averaging sheet).
    static func gpsLine(_ r: FieldRecorder) -> String {
        let s = gpsText(r)
        return s.hint.map { "\(s.title) — \($0)" } ?? s.title
    }

    private var recordingCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let track = model.field.tracks.first { $0.id == recorder.recordingTrackID }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(CP.rose.strong).frame(width: 10, height: 10)
                        .opacity(recorder.isPaused ? 0.3 : 1)
                    Text(recorder.isPaused ? "PAUSED" : "REC").font(.system(size: CP.fs(13), weight: .bold))
                        .foregroundStyle(recorder.isPaused ? CP.butter.strong : CP.rose.strong)
                    Text(track?.name ?? "").font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                }
                Text(Self.recordingStats(track: track, elapsed: recorder.recordingElapsed))
                    .font(CP.mono(13)).foregroundStyle(CP.ink)
                    .accessibilityIdentifier("fieldRecordingStats")
                HStack(spacing: CP.Space.s) {
                    if recorder.isPaused {
                        Button { model.resumeTrackRecording() } label: { Label("Resume", systemImage: "play.fill") }
                            .buttonStyle(FieldButtonStyle(tone: CP.sage))
                    } else {
                        Button { model.pauseTrackRecording() } label: { Label("Pause", systemImage: "pause.fill") }
                            .buttonStyle(FieldButtonStyle(tone: CP.butter))
                    }
                    Button { model.stopTrackRecording() } label: { Label("Stop", systemImage: "stop.fill") }
                        .buttonStyle(FieldButtonStyle(tone: CP.rose))
                        .accessibilityIdentifier("fieldStop")
                }
            }
        }
    }

    /// "12:34 · 850 m · 210 points" — time and distance without the pauses.
    static func recordingStats(track: FieldTrack?, elapsed d: TimeInterval) -> String {
        let length = track?.lengthM ?? 0
        let time = String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
        let dist = length >= 1000 ? "\(Fmt.number(length / 1000, decimals: 2)) km" : "\(Int(length.rounded())) m"
        return "\(time) · \(dist) · \(track?.points.count ?? 0) points"
    }
}

/// Field button in OCCA's soft tones (tone fill, text and icon in the tone's strong color): one line, 44 pt tall,
/// full width, so buttons side by side always match.
struct FieldButtonStyle: ButtonStyle {
    var tone: CP.Tone
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: CP.fs(14), weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(tone.strong)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(tone.fill.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(tone.strong.opacity(0.22)))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - New note

struct NewFieldNoteSheet: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var recorder: FieldRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var category: FieldNote.Category = .other
    @State private var text = ""
    @State private var photos: [UIImage] = []
    @State private var useGPS = true
    @State private var cameraOpen = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var heading: Double?
    // Bearing + distance offset (an object you can't walk to).
    @State private var useOffset = false
    @State private var bearing = ""
    @State private var distance = ""
    @State private var inPaces = false
    @State private var calibrating = false
    @State private var calibPaces = ""
    @AppStorage("paceLengthM") private var paceLengthM = PaceCount.defaultPaceM

    static let maxPhotos = 4

    var body: some View {
        NavigationStack {
            Form {
                Section("Position") {
                    Picker("Position", selection: $useGPS) {
                        Text("My GPS position").tag(true)
                        Text("Map center").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("noteUseGPS")
                    Text(positionText).font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                    Toggle("Offset — bearing and distance", isOn: $useOffset.animation())
                        .accessibilityIdentifier("noteOffset")
                    if useOffset { offsetRows }
                }
                Section("Category") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(FieldNote.Category.allCases, id: \.self) { c in
                            Button { category = c } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: c.icon).font(.system(size: 16, weight: .semibold))
                                    Text(c.label).font(.system(size: CP.fs(11))).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .foregroundStyle(category == c ? .white : Color(hexString: c.colorHex))
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(category == c ? Color(hexString: c.colorHex) : Color(hexString: c.colorHex).opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: CP.Radius.control))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(c.label)
                            .accessibilityAddTraits(category == c ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Note") {
                    TextField("e.g. boulder 1.5 m, fence passable?", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("noteText")
                }
                Section {
                    if !photos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(photos.indices, id: \.self) { i in
                                    Image(uiImage: photos[i]).resizable().scaledToFill()
                                        .frame(width: 84, height: 84).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button { photos.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6)) }
                                                .padding(3)
                                        }
                                }
                            }
                        }
                    }
                    if photos.count < Self.maxPhotos {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { heading = model.live.deviceHeading; cameraOpen = true } label: { Label("Take photo", systemImage: "camera") }
                        }
                        PhotosPicker(selection: $libraryItem, matching: .images) { Label("Choose photo", systemImage: "photo.on.rectangle") }
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Up to \(Self.maxPhotos) photos, resized to 2048 px (about 300 KB each), kept in the project.")
                }
            }
            .navigationTitle("New field note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.accessibilityIdentifier("noteSave")
                }
            }
            .fullScreenCover(isPresented: $cameraOpen) {
                CameraPicker { image in if let image { photos.append(image) } }
                    .ignoresSafeArea()
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { photos.append(img) }
                    libraryItem = nil
                }
            }
        }
        .onAppear {
            recorder.setWantsNoteFix(true)
            useGPS = recorder.hasFix
        }
        .onDisappear { recorder.setWantsNoteFix(false) }
    }

    /// Bearing (typed, or the compass) and distance (meters, or paces × the calibrated pace length).
    @ViewBuilder private var offsetRows: some View {
        HStack {
            Text("Bearing")
            TextField("0–360", text: $bearing).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .accessibilityIdentifier("offsetBearing")
            Text("°").foregroundStyle(CP.inkMuted)
            Button { if let h = model.live.deviceHeading { bearing = String(Int(h.rounded()) % 360) } } label: {
                Label("Compass", systemImage: "location.north.line")
            }
            .buttonStyle(.bordered)
            .disabled(model.live.deviceHeading == nil)
            .help("Use the direction the iPad's top edge points")
        }
        HStack {
            Text("Distance")
            TextField(inPaces ? "paces" : "meters", text: $distance).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .accessibilityIdentifier("offsetDistance")
            Picker("Unit", selection: $inPaces) {
                Text("m").tag(false)
                Text("paces").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
        }
        if inPaces {
            HStack {
                Text("1 pace (2 steps) = \(Fmt.number(paceLengthM, decimals: 2)) m").font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                Spacer()
                Button(calibrating ? "Cancel" : "Calibrate") { calibrating.toggle() }
            }
            if calibrating {
                HStack {
                    Text("Paces for 100 m")
                    TextField("e.g. 64", text: $calibPaces).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Button("Set") {
                        if let p = Double(calibPaces.replacingOccurrences(of: ",", with: ".")),
                           let l = PaceCount.paceLength(knownDistanceM: 100, paces: p) {
                            paceLengthM = l
                            calibrating = false
                        }
                    }
                }
                Text("Walk a known 100 m (e.g. measured on the map) and count every second step.")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            }
        }
    }

    private func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    private var offsetValue: (bearingDeg: Double, distanceM: Double, paces: Double?)? {
        guard useOffset, let b = number(bearing), let d = number(distance), d > 0 else { return nil }
        let meters = inPaces ? d * paceLengthM : d
        return ((b.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360), meters, inPaces ? d : nil)
    }

    private var positionText: String {
        if let o = offsetValue {
            return "\(FieldNoteDetail.distanceText(o.distanceM)) at \(FieldNoteDetail.headingText(o.bearingDeg)) from \(useGPS ? "your GPS position" : "the map center")."
        }
        if useGPS {
            if let (_, acc) = recorder.currentPosition { return "At your GPS position (±\(Int(acc.rounded())) m)." }
            return "Waiting for GPS… The map center is used if there is no fix when you save."
        }
        return "At the center of the visible map."
    }

    private func save() {
        let data = photos.compactMap { FieldPhoto.jpeg($0) }
        if useOffset, offsetValue == nil {
            model.notice = "Enter a bearing (0–360°) and a distance for the offset, or turn the offset off."
            return
        }
        if model.addFieldNote(category: category, text: text, photos: data, heading: heading, atGPS: useGPS, offset: offsetValue) != nil {
            dismiss()
        }
    }
}

/// Photo storage size: longest side ≤ 2048 px, JPEG quality 0.7 (±300 KB).
enum FieldPhoto {
    static let maxSide: CGFloat = 2048

    static func jpeg(_ image: UIImage) -> Data? {
        let s = image.size
        let k = min(1, maxSide / max(s.width, s.height, 1))
        let size = CGSize(width: (s.width * k).rounded(), height: (s.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7)
    }
}

/// System camera (iPad).
struct CameraPicker: UIViewControllerRepresentable {
    var onDone: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (UIImage?) -> Void
        init(onDone: @escaping (UIImage?) -> Void) { self.onDone = onDone }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDone(nil)
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Averaging

struct AveragingSheet: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var recorder: FieldRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var seconds = 20.0
    @State private var category: FieldNote.Category = .control
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: CP.Space.l) {
                if let r = recorder.averagingResult {
                    result(r)
                } else if let a = recorder.averaging {
                    running(a)
                } else {
                    setup
                }
                Spacer(minLength: 0)
            }
            .padding(CP.Space.l)
            .navigationTitle("Average position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { recorder.cancelAveraging(); dismiss() }
                }
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            Text("Stand still at the spot (e.g. a control site or a boulder). OCCA averages the GPS fixes into one more accurate position.")
                .font(.system(size: CP.fs(14))).foregroundStyle(CP.ink)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Duration", selection: $seconds) {
                Text("10 s").tag(10.0); Text("20 s").tag(20.0); Text("30 s").tag(30.0)
            }
            .pickerStyle(.segmented)
            Text(FieldCaptureSection.gpsLine(recorder)).font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button { recorder.startAveraging(seconds: seconds) } label: {
                Label("Start — hold here", systemImage: "scope")
            }
            .buttonStyle(FieldButtonStyle(tone: CP.sky))
            .accessibilityIdentifier("averageStart")
        }
        .onAppear { recorder.requestPermission() }
    }

    private func running(_ a: FieldRecorder.AveragingState) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            VStack(spacing: CP.Space.m) {
                ZStack {
                    Circle().stroke(CP.line, lineWidth: 10)
                    Circle().trim(from: 0, to: a.progress).stroke(CP.sky.strong, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(max(0, Int(ceil(a.targetS - Date().timeIntervalSince(a.started))))) s")
                            .font(.system(size: CP.fs(28), weight: .bold, design: .rounded))
                        Text("hold still").font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    }
                }
                .frame(width: 150, height: 150)
                if let r = a.averager.result {
                    Text("±\(Fmt.number(r.accuracyM, decimals: 1)) m · \(r.samples) fixes").font(CP.mono(15))
                        .accessibilityIdentifier("averageLive")
                } else {
                    Text("Waiting for GPS…").font(.system(size: CP.fs(14))).foregroundStyle(CP.inkMuted)
                }
            }
        }
    }

    private func result(_ r: PositionAverager.Result) -> some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            Label("±\(Fmt.number(r.accuracyM, decimals: 1)) m from \(r.samples) fixes in \(Int(r.durationS.rounded())) s",
                  systemImage: "checkmark.seal.fill")
                .font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.sage.strong)
                .accessibilityIdentifier("averageResult")
            Picker("Category", selection: $category) {
                ForEach(FieldNote.Category.allCases, id: \.self) { Label($0.label, systemImage: $0.icon).tag($0) }
            }
            TextField("Note (optional)", text: $text)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button { recorder.cancelAveraging() } label: { Label("Measure again", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(FieldButtonStyle(tone: CP.butter))
                Button { model.saveAveragedPosition(category: category, text: text); dismiss() } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(FieldButtonStyle(tone: CP.sage))
                .accessibilityIdentifier("averageSave")
            }
        }
    }
}

/// Small "REC 12:34 · 1.2 km" capsule at the top of the map while a track is recording; tap = pause/resume.
struct RecordingBadge: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var recorder: FieldRecorder

    var body: some View {
        if recorder.isRecording {
            VStack {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let track = model.field.tracks.first { $0.id == recorder.recordingTrackID }
                    Button {
                        recorder.isPaused ? model.resumeTrackRecording() : model.pauseTrackRecording()
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(CP.rose.strong).frame(width: 9, height: 9).opacity(recorder.isPaused ? 0.3 : 1)
                            Text(recorder.isPaused ? "PAUSED" : "REC").font(.system(size: 12, weight: .bold))
                            Text(FieldCaptureSection.recordingStats(track: track, elapsed: recorder.recordingElapsed))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(CP.ink)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(CP.rose.strong.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recordingBadge")
                    .accessibilityLabel(recorder.isPaused ? "Track paused, tap to resume" : "Recording track, tap to pause")
                }
                .padding(.top, CP.isMac ? 8 : 64)
                Spacer()
            }
            .allowsHitTesting(true)
        }
    }
}
