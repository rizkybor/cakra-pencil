import CakraCore
import MapKit
import SwiftUI
import UIKit

// MARK: - State

/// A sketch being drawn on the map (Field panel / field mode › Draw): strokes in UTM meters (the project zone).
struct FieldSketchDraft: Equatable {
    var strokes: [[Point2D]] = []
    /// Redrawing the sketch of this note; nil = a new sketch note.
    var noteID: UUID?
    /// Done was tapped: the note editor is open.
    var finishing = false
}

/// Sketch notes: draw or mark on the map in the field (finger, Apple Pencil, mouse), then save the drawing with a note.
/// iPad and Mac. Field data is not part of the drawing undo history; Undo stroke works while drawing.
extension WorkspaceModel {
    /// Start drawing; `redraw`: replace the sketch of that note (or give it one).
    func startFieldSketch(redraw noteID: UUID? = nil) {
        guard LicenseManager.shared.require(.fieldwork) else { return }
        guard zone != nil else { notice = "Lock the map area first (Map tab)."; return }
        trackLineID = nil
        fieldLinePreview = []
        let existing = noteID.flatMap { id in field.notes.first { $0.id == id }?.sketch } ?? []
        fieldSketch = FieldSketchDraft(strokes: existing, noteID: noteID)
    }

    func addSketchStroke(_ points: [Point2D]) {
        guard !points.isEmpty, fieldSketch != nil else { return }
        fieldSketch?.strokes.append(points)
    }

    func undoSketchStroke() {
        guard var d = fieldSketch, !d.strokes.isEmpty else { return }
        d.strokes.removeLast()
        fieldSketch = d
    }
    func clearSketch() { fieldSketch?.strokes = [] }
    func cancelFieldSketch() { fieldSketch = nil }

    /// Done: a new sketch opens the note editor; a redrawn sketch is saved on its note right away.
    func finishFieldSketch() {
        guard let d = fieldSketch, !d.strokes.isEmpty else { return }
        guard let id = d.noteID else {
            fieldSketch?.finishing = true
            return
        }
        let hadSketch = field.notes.first { $0.id == id }?.hasSketch == true
        updateNote(id) { n in
            n.sketch = d.strokes
            n.sketchEditedAt = Date()
            // A sketch note's pin follows its drawing; a GPS / averaged note keeps its measured position.
            if hadSketch, n.averaging == nil, n.accuracyM == nil, let a = FieldNote.sketchAnchor(d.strokes) { n.position = a }
            n.isShown = true
        }
        fieldSketch = nil
        notice = hadSketch ? "Sketch updated." : "Sketch added to the note."
    }

    /// Save the drawn sketch as a new note (from the note editor).
    @discardableResult
    func saveSketchNote(category: FieldNote.Category, text: String, photos: [Data], heading: Double?) -> FieldNote? {
        guard let d = fieldSketch, let anchor = FieldNote.sketchAnchor(d.strokes) else { return nil }
        let n = addFieldNote(category: category, text: text, photos: photos, heading: heading, atGPS: false, position: anchor,
                             sketch: d.strokes)
        if n != nil {
            fieldSketch = nil
            notice = "Sketch note saved."
        }
        return n
    }
}

// MARK: - Drawing layer

/// Drawing layer above the map while a sketch is drawn: one finger, Apple Pencil or the mouse draws; two fingers
/// still pan and zoom (the canvas's two-finger gestures take over and cancel the stroke in progress), and a trackpad
/// scrolls and pinches as usual. Strokes are drawn in screen space and follow the map.
final class FieldSketchView: UIView {
    weak var mapView: MKMapView?
    var zone: UTMZone?
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            isHidden = !isActive
            if !isActive { cancelStroke() }
        }
    }
    var strokes: [[Point2D]] = [] {
        didSet { if strokes != oldValue { setNeedsDisplay() } }
    }
    var onStroke: (([Point2D]) -> Void)?

    /// Bright red-orange with a white halo: readable on imagery and on the map colours.
    static let ink = UIColor(red: 1, green: 0.22, blue: 0.12, alpha: 1)

    private var live: [CGPoint] = []
    private var tracked: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
        isMultipleTouchEnabled = false
        contentMode = .redraw
        accessibilityIdentifier = "fieldSketchCanvas"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The sketch bar's frame in window coordinates: taps on its buttons must not also draw a dot underneath.
    static var barFrame: CGRect = .null

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isActive, self.point(inside: point, with: event) else { return nil }
        if Self.barFrame.insetBy(dx: -6, dy: -6).contains(convert(point, to: nil)) { return nil }
        // A second finger belongs to the two-finger pan / zoom.
        return (event?.allTouches?.count ?? 1) <= 1 ? self : nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracked == nil, let t = touches.first else { return }
        tracked = t
        live = [t.preciseLocation(in: self)]
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = tracked, touches.contains(t) else { return }
        for c in event?.coalescedTouches(for: t) ?? [t] {
            let p = c.preciseLocation(in: self)
            if let last = live.last, hypot(p.x - last.x, p.y - last.y) < 1.5 { continue }
            live.append(p)
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = tracked, touches.contains(t) else { return }
        let p = t.preciseLocation(in: self)
        if live.last != p { live.append(p) }
        commit()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = tracked, touches.contains(t) else { return }
        cancelStroke()
    }

    private func cancelStroke() {
        tracked = nil
        live = []
        setNeedsDisplay()
    }

    private func commit() {
        defer { cancelStroke() }
        guard let mapView, let zone else { return }
        let pts = live.map { p -> Point2D in
            let c = mapView.convert(p, toCoordinateFrom: self)
            return zone.project(LatLon(lat: c.latitude, lon: c.longitude))
        }
        guard let first = pts.first else { return }
        // Simplified to about half a screen point: small files, the shape as drawn.
        let tolerance = 0.5 * metersPerPoint
        let simple = pts.count > 2 ? ContourGenerator.simplify(pts, tolerance: tolerance) : pts
        onStroke?(simple.isEmpty ? [first] : simple)
    }

    private var metersPerPoint: Double {
        guard let mapView, bounds.width > 0 else { return 1 }
        let a = MKMapPoint(mapView.convert(CGPoint(x: bounds.midX, y: bounds.midY), toCoordinateFrom: self))
        let b = MKMapPoint(mapView.convert(CGPoint(x: bounds.midX + 100, y: bounds.midY), toCoordinateFrom: self))
        return a.distance(to: b) / 100
    }

    private func screen(_ p: Point2D) -> CGPoint {
        guard let mapView, let zone else { return .zero }
        let ll = zone.unproject(p)
        return mapView.convert(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon), toPointTo: self)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let all = strokes.map { $0.map(screen) } + (live.isEmpty ? [] : [live])
        for (width, color) in [(7.0, UIColor.white.withAlphaComponent(0.9)), (3.5, Self.ink)] {
            ctx.setStrokeColor(color.cgColor)
            ctx.setFillColor(color.cgColor)
            for s in all {
                guard let first = s.first else { continue }
                if s.count == 1 {
                    // A tap: a dot.
                    let r = width
                    ctx.fillEllipse(in: CGRect(x: first.x - r, y: first.y - r, width: 2 * r, height: 2 * r))
                    continue
                }
                ctx.beginPath()
                ctx.move(to: first)
                for p in s.dropFirst() { ctx.addLine(to: p) }
                ctx.setLineWidth(width)
                ctx.strokePath()
            }
        }
    }
}

// MARK: - Bar

/// Small bar while drawing: Undo stroke, Clear, Cancel, Done. Done opens the note editor (category, text, photos);
/// for a redrawn sketch it saves straight away.
struct FieldSketchBar: View {
    @ObservedObject var model: WorkspaceModel

    private var strokes: Int { model.fieldSketch?.strokes.count ?? 0 }
    private var redrawing: Bool { model.fieldSketch?.noteID != nil }

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: CP.Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Label(redrawing ? "Redraw sketch" : "Draw on the map", systemImage: "scribble.variable")
                        .font(.system(size: CP.fs(14), weight: .semibold))
                        .foregroundStyle(CP.ink)
                    Text(strokes == 0 ? (CP.isMac ? "Drag to draw · scroll or pinch to move" : "One finger or Pencil draws · two fingers move")
                         : "\(strokes) stroke\(strokes == 1 ? "" : "s")")
                        .font(.system(size: CP.fs(11)))
                        .foregroundStyle(CP.inkMuted)
                        .accessibilityIdentifier("sketchStrokeCount")
                }
                .fixedSize()
                .padding(.trailing, CP.Space.xs)
                barButton("arrow.uturn.backward", "Undo stroke", id: "sketchUndo") { model.undoSketchStroke() }
                    .disabled(strokes == 0)
                barButton("trash", "Clear", id: "sketchClear") { model.clearSketch() }
                    .disabled(strokes == 0)
                Button("Cancel") { model.cancelFieldSketch() }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("sketchCancel")
                Button("Done") { model.finishFieldSketch() }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .disabled(strokes == 0)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("sketchDone")
            }
            .padding(.horizontal, CP.Space.m)
            .padding(.vertical, CP.Space.s)
            .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel, style: .continuous).strokeBorder(CP.line))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { FieldSketchView.barFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in FieldSketchView.barFrame = f }
                    .onDisappear { FieldSketchView.barFrame = .null }
            })
            .padding(.bottom, model.fieldMode ? 36 : CP.Space.xl)
            .padding(.horizontal, CP.Space.m)
            .frame(maxWidth: .infinity, alignment: model.fieldMode ? .center : .leading)
        }
        .sheet(isPresented: Binding(get: { model.fieldSketch?.finishing == true },
                                    set: { if !$0 { model.fieldSketch?.finishing = false } })) {
            NewFieldNoteSheet(model: model, recorder: model.recorder, sketch: model.fieldSketch?.strokes)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fieldSketchBar")
    }

    private func barButton(_ icon: String, _ name: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: CP.fs(15), weight: .semibold))
        }
        .buttonStyle(SecondaryButtonStyle(compact: true))
        .help(name)
        .accessibilityLabel(name)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Preview

/// The sketch scaled into a small box (note editor, note detail).
struct FieldSketchPreview: View {
    let strokes: [[Point2D]]
    var color: Color = Color(uiColor: FieldSketchView.ink)

    var body: some View {
        Canvas { ctx, size in
            let pts = strokes.flatMap { $0 }
            guard let b = Rect2D(points: pts) else { return }
            let w = max(b.maxX - b.minX, 1), h = max(b.maxY - b.minY, 1)
            let pad: CGFloat = 10
            let k = min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h)
            let ox = (size.width - w * k) / 2, oy = (size.height - h * k) / 2
            func pt(_ p: Point2D) -> CGPoint { CGPoint(x: ox + (p.x - b.minX) * k, y: size.height - oy - (p.y - b.minY) * k) }
            for s in strokes {
                guard let first = s.first else { continue }
                if s.count == 1 {
                    let c = pt(first)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(color))
                    continue
                }
                var path = Path()
                path.move(to: pt(first))
                for p in s.dropFirst() { path.addLine(to: pt(p)) }
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityLabel("Sketch preview")
    }

    /// "2 strokes · 85 m"
    static func summary(_ strokes: [[Point2D]]) -> String {
        let n = FieldNote(position: .init(x: 0, y: 0), sketch: strokes)
        var parts = ["\(strokes.count) stroke\(strokes.count == 1 ? "" : "s")", TrackLineEditor.meters(n.sketchLengthM)]
        if n.sketchIsClosed { parts.append("closed shape") }
        return parts.joined(separator: " · ")
    }
}
