import CakraCore
import PencilKit
import SwiftUI
import UIKit

// MARK: - Photo + markup

/// A field photo with its markup drawing on top (if any). The markup is a PencilKit drawing stored next to the photo
/// (`<photo>.drawing`) in the photo's pixel coordinates, so the original photo is never changed.
enum FieldPhotoImage {
    static func load(photo url: URL, markup: URL?, maxSide: CGFloat? = nil) -> UIImage? {
        guard let photo = UIImage(contentsOfFile: url.path) else { return nil }
        var image = photo
        if let markup, let data = try? Data(contentsOf: markup), let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty {
            let size = CGSize(width: photo.size.width * photo.scale, height: photo.size.height * photo.scale)
            var overlay: UIImage?
            // Ink colors as drawn (PencilKit would invert black / white in dark mode).
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                overlay = drawing.image(from: CGRect(origin: .zero, size: size), scale: 1)
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                photo.draw(in: CGRect(origin: .zero, size: size))
                overlay?.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        if let maxSide { return image.preparingThumbnail(of: CGSize(width: maxSide, height: maxSide)) ?? image }
        return image
    }

    /// Changes whenever the markup file changes (to reload thumbnails / the viewer).
    static func stamp(_ markup: URL?) -> String {
        guard let markup, let date = (try? FileManager.default.attributesOfItem(atPath: markup.path))?[.modificationDate] as? Date else { return "-" }
        return String(date.timeIntervalSince1970)
    }
}

extension WorkspaceModel {
    func markupURL(_ photo: String) -> URL { fieldPhotoURL(FieldNote.markupFile(for: photo)) }

    /// The markup file of a photo if the note has one.
    func markupURL(_ photo: String, in note: FieldNote) -> URL? { note.hasMarkup(photo) ? markupURL(photo) : nil }

    /// Save (or with `nil` / an empty drawing remove) the markup of a photo.
    func saveMarkup(noteID: UUID, photo: String, drawing: Data?) {
        let url = markupURL(photo)
        if let drawing {
            do {
                try drawing.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                notice = "Couldn't save the markup: \(error.localizedDescription)"
                return
            }
            updateNote(noteID) { n in if !n.hasMarkup(photo) { n.markedPhotos = (n.markedPhotos ?? []) + [photo] } }
        } else {
            try? FileManager.default.removeItem(at: url)
            updateNote(noteID) { n in
                n.markedPhotos?.removeAll { $0 == photo }
                if n.markedPhotos?.isEmpty == true { n.markedPhotos = nil }
            }
        }
    }
}

// MARK: - Markup editor

/// Draw on a field photo with Apple Pencil (or a finger, or the mouse / trackpad on Mac): circle a boulder, mark a
/// fence, add an arrow. PencilKit tools (pen, marker, eraser, lasso, ruler, colors). Saved as a separate drawing.
struct PhotoMarkupView: View {
    @ObservedObject var model: WorkspaceModel
    let noteID: UUID
    let photo: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = MarkupController()
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = UIImage(contentsOfFile: model.fieldPhotoURL(photo).path) {
                    MarkupCanvas(image: image, initial: initialDrawing, controller: controller)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("Markup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Group {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("markupCancel")
                }.buttonStyle(SecondaryButtonStyle(compact: true)) }.plainBar()
                ToolbarItem(placement: .primaryAction) { Group {
                    Button(role: .destructive) { confirmClear = true } label: { Label("Clear", systemImage: "trash") }
                        .help("Remove the whole markup")
                        .accessibilityIdentifier("markupClear")
                }.buttonStyle(PastelButtonStyle(tone: CP.rose)) }.plainBar()
                ToolbarItem(placement: .confirmationAction) { Group {
                    Button("Done") {
                        let d = controller.drawingInPhotoPixels()
                        model.saveMarkup(noteID: noteID, photo: photo, drawing: d.strokes.isEmpty ? nil : d.dataRepresentation())
                        dismiss()
                    }
                    .accessibilityIdentifier("markupDone")
                }.buttonStyle(PrimaryButtonStyle(compact: true)) }.plainBar()
            }
            .confirmationDialog("Remove the whole markup?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Remove markup", role: .destructive) { controller.clear() }
            }
        }
    }

    private var initialDrawing: PKDrawing? {
        guard let data = try? Data(contentsOf: model.markupURL(photo)) else { return nil }
        return try? PKDrawing(data: data)
    }
}

/// Holds the canvas so the toolbar can read the drawing; converts between view and photo pixel coordinates.
@MainActor
final class MarkupController: ObservableObject {
    weak var canvas: PKCanvasView?
    /// Screen points per photo pixel (the photo is shown aspect-fit).
    var scale: CGFloat = 1
    var toolPicker: PKToolPicker?

    func drawingInPhotoPixels() -> PKDrawing {
        guard let canvas, scale > 0 else { return PKDrawing() }
        return canvas.drawing.transformed(using: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
    }

    func clear() { canvas?.drawing = PKDrawing() }
}

/// The photo aspect-fit with a transparent PencilKit canvas exactly on top of it.
struct MarkupCanvas: UIViewRepresentable {
    let image: UIImage
    let initial: PKDrawing?
    let controller: MarkupController

    func makeUIView(context: Context) -> MarkupContainer {
        let v = MarkupContainer(image: image, initial: initial, controller: controller)
        DispatchQueue.main.async { v.showTools() }
        return v
    }

    func updateUIView(_ uiView: MarkupContainer, context: Context) {}

    static func dismantleUIView(_ uiView: MarkupContainer, coordinator: ()) { uiView.hideTools() }
}

final class MarkupContainer: UIView {
    private let imageView = UIImageView()
    let canvas = PKCanvasView()
    private let pixelSize: CGSize
    private var initial: PKDrawing?
    private weak var controller: MarkupController?
    private var lastScale: CGFloat = 0

    init(image: UIImage, initial: PKDrawing?, controller: MarkupController) {
        pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        self.initial = initial
        self.controller = controller
        super.init(frame: .zero)
        backgroundColor = .black
        imageView.image = image
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput           // Apple Pencil, finger, mouse / trackpad
        canvas.tool = PKInkingTool(.pen, color: .systemRed, width: 6)
        canvas.isScrollEnabled = false
        canvas.accessibilityIdentifier = "markupCanvas"
        addSubview(canvas)
        controller.canvas = canvas
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard pixelSize.width > 0, pixelSize.height > 0, bounds.width > 0 else { return }
        let k = min(bounds.width / pixelSize.width, bounds.height / pixelSize.height)
        let size = CGSize(width: pixelSize.width * k, height: pixelSize.height * k)
        let rect = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        imageView.frame = rect
        canvas.frame = rect
        // Keep the drawing on the photo when the view size changes (rotation, window resize on Mac).
        if let first = initial {
            canvas.drawing = first.transformed(using: CGAffineTransform(scaleX: k, y: k))
            initial = nil
        } else if lastScale > 0, abs(lastScale - k) > 0.0001 {
            canvas.drawing = canvas.drawing.transformed(using: CGAffineTransform(scaleX: k / lastScale, y: k / lastScale))
        }
        lastScale = k
        controller?.scale = k
    }

    func showTools() {
        // Red pen to start with (marking things on a photo); the picker would otherwise start with its black pen.
        let red = PKInkingTool(.pen, color: .systemRed, width: 6)
        let picker = PKToolPicker()
        picker.selectedTool = red
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        controller?.toolPicker = picker
        canvas.becomeFirstResponder()
        canvas.tool = red
        DispatchQueue.main.async { [weak self] in
            picker.selectedTool = red
            self?.canvas.tool = red
        }
    }

    func hideTools() {
        if let picker = controller?.toolPicker {
            picker.setVisible(false, forFirstResponder: canvas)
            picker.removeObserver(canvas)
        }
        canvas.resignFirstResponder()
    }
}
