import CakraCore
import SwiftUI
import UIKit

// MARK: - Ready for the field

/// Checklist before going out: HD images of the area, contours, symbol sets, storage, battery, location permission —
/// with "Download missing" while there is still internet.
struct ReadyCheckSheet: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1.5)) { _ in
                let r = model.fieldReadiness()
                List {
                    Section {
                        summary(r)
                    }
                    Section("Offline map data") {
                        row(r.areaLocked, "Map area locked", r.areaLocked ? "The frame is fixed on the map." : "Lock the map area first (Map tab).")
                        ForEach(r.imagery, id: \.0) { type, ok in
                            row(ok, "HD image — \(type.label)", ok ? "Saved for this area." : (model.imageryProgress ?? "Not downloaded yet."))
                        }
                        row(r.contours, "Contours", r.contours ? "Elevation data saved in the project." : contourText)
                        row(true, "Symbol sets", "Built into OCCA (ISOM 2017-2, ISSprOM 2019-2) — always offline.")
                    }
                    Section("Device") {
                        row(!r.lowStorage, "Free storage", r.freeBytes.map { StorageInfo.format($0) + " free" + (r.lowStorage ? " — less than 500 MB" : "") } ?? "Unknown")
                        row(!r.lowBattery, "Battery", r.battery.map { "\(Int(($0 * 100).rounded())) %" + (r.lowBattery ? " — charge before going out" : "") } ?? "Unknown (simulator)")
                        row(r.location == .authorizedWhenInUse || r.location == .authorizedAlways, "Location permission", locationText(r))
                        row(model.recorder.hasFix, "Position source", model.recorder.isExternalGNSS
                            ? "External GNSS receiver connected."
                            : model.recorder.hasFix ? "Built-in GPS. An external GNSS receiver (Bluetooth) gives 1–3 m and works on Wi-Fi iPads."
                            : "No fix yet. Wi-Fi iPads have no GPS chip — connect an external GNSS receiver (Bluetooth).")
                    }
                    if !r.offlineReady {
                        Section {
                            Button { model.downloadMissingForField() } label: {
                                Label("Download missing", systemImage: "icloud.and.arrow.down")
                            }
                            .disabled(!r.areaLocked)
                            .accessibilityIdentifier("readyDownload")
                        } footer: {
                            Text("Downloads need internet — do this before you leave.")
                        }
                    }
                }
            }
            .navigationTitle("Ready for the field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var contourText: String {
        switch model.contourStatus {
        case let .downloading(done, total): return "Downloading \(done) / \(total) tiles…"
        case .generating: return "Generating…"
        case let .failed(msg): return msg
        default: return "Not downloaded yet."
        }
    }

    private func locationText(_ r: WorkspaceModel.FieldReadiness) -> String {
        switch r.location {
        case .authorizedWhenInUse, .authorizedAlways: return "Allowed."
        case .denied, .restricted: return "Off — turn it on in Settings › Privacy & Security."
        default: return "Asked when you first record or average."
        }
    }

    private func summary(_ r: WorkspaceModel.FieldReadiness) -> some View {
        HStack(spacing: CP.Space.m) {
            Image(systemName: r.offlineReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(r.offlineReady ? CP.sage.strong : CP.butter.strong)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.offlineReady ? "Ready for the field" : "Not ready yet")
                    .font(.system(size: CP.fs(17), weight: .semibold))
                Text(r.offlineReady ? "The map works without internet." : "Some map data is missing offline.")
                    .font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readySummary")
    }

    private func row(_ ok: Bool, _ title: String, _ detail: String) -> some View {
        HStack(spacing: CP.Space.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? CP.sage.strong : CP.peach.strong)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: CP.fs(15)))
                Text(detail).font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Field mode

/// Field mode (iPad): the map full screen with a high-contrast header (exit, GPS, battery, recording) and big buttons
/// at the bottom (record / pause / stop, note, average, follow me, touch lock). The screen stays on.
struct FieldModeOverlay: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var recorder: FieldRecorder
    @EnvironmentObject private var library: SymbolLibrary
    @State private var locked = false
    @State private var addingNote = false
    @State private var averagingOpen = false
    @State private var vegetationOpen = false
    @State private var unlockProgress = 0.0

    private static let ink = Color(red: 0.08, green: 0.09, blue: 0.08)
    private static let card = Color(red: 0.12, green: 0.13, blue: 0.12).opacity(0.94)

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                if !locked { buttons }
            }
            .padding(CP.Space.m)

            if locked { lockLayer }
        }
        .sheet(isPresented: $addingNote) { NewFieldNoteSheet(model: model, recorder: recorder) }
        .sheet(isPresented: $averagingOpen) { AveragingSheet(model: model, recorder: recorder) }
        .sheet(isPresented: $vegetationOpen) { VegetationSheet(model: model, recorder: recorder) }
        // A note pin tapped on the map (not while locked).
        .sheet(isPresented: Binding(get: { model.openFieldNoteID != nil && !locked }, set: { if !$0 { model.openFieldNoteID = nil } })) {
            if let id = model.openFieldNoteID {
                NavigationStack {
                    FieldNoteDetail(model: model, noteID: id)
                        .padding(.horizontal, CP.Space.l)
                        .navigationTitle("Field note")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.openFieldNoteID = nil } } }
                }
                .environmentObject(library)
            }
        }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: CP.Space.m) {
                Button { model.exitFieldMode() } label: {
                    Label("Exit", systemImage: "xmark").font(.system(size: 17, weight: .bold))
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(locked)
                .accessibilityLabel("Exit field mode")
                .accessibilityIdentifier("fieldModeExit")

                let gps = FieldCaptureSection.gpsText(recorder)
                Label(gps.title, systemImage: "location.fill")
                    .foregroundStyle(gps.good ? Color(red: 0.55, green: 0.9, blue: 0.6) : Color(red: 1, green: 0.75, blue: 0.4))
                    .accessibilityIdentifier("fieldModeGPS")
                if recorder.isRecording {
                    let track = model.field.tracks.first { $0.id == recorder.recordingTrackID }
                    HStack(spacing: 6) {
                        Circle().fill(Color(red: 1, green: 0.35, blue: 0.4)).frame(width: 10, height: 10).opacity(recorder.isPaused ? 0.3 : 1)
                        Text(FieldCaptureSection.recordingStats(track: track, elapsed: recorder.recordingElapsed))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    }
                }
                Spacer(minLength: 0)
                batteryLabel
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, CP.Space.m).padding(.vertical, 8)
            .background(Self.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var batteryLabel: some View {
        let level = UIDevice.current.batteryLevel
        let pct = level < 0 ? nil : Int((level * 100).rounded())
        let icon = pct.map { $0 > 75 ? "battery.100" : $0 > 50 ? "battery.75" : $0 > 25 ? "battery.50" : "battery.25" } ?? "battery.100"
        return Label(pct.map { "\($0) %" } ?? "—", systemImage: icon)
            .foregroundStyle((pct ?? 100) < 25 ? Color(red: 1, green: 0.5, blue: 0.45) : .white)
            .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
    }

    private var buttons: some View {
        HStack(spacing: CP.Space.m) {
            if !DeviceCapabilities.canRecordTracks {
                // Wi-Fi-only iPad: no GPS chip, no track recorder.
                EmptyView()
            } else if recorder.isRecording {
                if recorder.isPaused {
                    bigButton("play.fill", "Resume", tone: Color(red: 0.35, green: 0.75, blue: 0.45)) { model.resumeTrackRecording() }
                } else {
                    bigButton("pause.fill", "Pause", tone: Color(red: 0.95, green: 0.75, blue: 0.3)) { model.pauseTrackRecording() }
                }
                bigButton("stop.fill", "Stop", tone: Color(red: 1, green: 0.35, blue: 0.4), id: "fieldModeStop") { model.stopTrackRecording() }
            } else {
                bigButton("record.circle", "Record", tone: Color(red: 1, green: 0.35, blue: 0.4), id: "fieldModeRecord") { model.startTrackRecording() }
            }
            bigButton("mappin.and.ellipse", "Note", tone: Color(red: 0.45, green: 0.85, blue: 0.55), id: "fieldModeNote") { addingNote = true }
            bigButton("scope", "Average", tone: Color(red: 0.5, green: 0.75, blue: 1)) { averagingOpen = true }
            bigButton("leaf.fill", "Vegetation", tone: Color(red: 1, green: 0.8, blue: 0.4)) { vegetationOpen = true }
            bigButton("location.fill", "Follow me", tone: .white) { model.mapCommand = MapCommand(kind: .followUser) }
            bigButton("lock.fill", "Lock", tone: .white, id: "fieldModeLock") { locked = true }
        }
        .padding(CP.Space.m)
        .background(Self.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func bigButton(_ icon: String, _ title: String, tone: Color, id: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 26, weight: .bold))
                    .frame(height: 32)                        // same height for every icon, so the labels line up
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(tone)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id ?? "fieldMode\(title.replacingOccurrences(of: " ", with: ""))")
    }

    /// Touch lock: the map and buttons ignore touches (bag, rain, gloves); hold the unlock button for 1 s.
    private var lockLayer: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {}
                .gesture(DragGesture(minimumDistance: 0))
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 6)
                    Circle().trim(from: 0, to: unlockProgress).stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "lock.open.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 76, height: 76)
                .background(Self.card, in: Circle())
                .onLongPressGesture(minimumDuration: 1, maximumDistance: 40) {
                    locked = false
                    unlockProgress = 0
                } onPressingChanged: { pressing in
                    withAnimation(pressing ? .linear(duration: 1) : .easeOut(duration: 0.2)) { unlockProgress = pressing ? 1 : 0 }
                }
                .accessibilityLabel("Hold to unlock")
                .accessibilityIdentifier("fieldModeUnlock")
                Text("Locked — hold to unlock").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Self.card, in: Capsule())
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fieldModeLocked")
    }
}
