import CakraCore
import MapKit
import UIKit

/// Project card preview: satellite imagery of the frame area + vector objects and sketch on top, saved as
/// `thumbnail.jpg` in the .cakra package. Without internet, the preview is still made on a paper background.
enum ProjectThumbnail {
    static let fileName = "thumbnail.jpg"
    static let width: CGFloat = 560

    static func url(in package: URL) -> URL { package.appendingPathComponent(fileName) }

    @MainActor
    static func render(_ doc: ProjectDocument) async -> Data? {
        guard let frame = doc.project.frame, let zone = doc.project.zone else { return nil }
        let corners = frame.corners.map { p -> CLLocationCoordinate2D in
            let ll = zone.unproject(p)
            return CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon)
        }
        let pts = corners.map(MKMapPoint.init)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let rect = MKMapRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let size = CGSize(width: width, height: (width * rect.height / rect.width).rounded())

        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = size
        options.scale = 2
        options.preferredConfiguration = MKImageryMapConfiguration()
        let snapshot = try? await MKMapSnapshotter(options: options).start()

        // Convert UTM → image point, via the snapshot if available, otherwise linearly within mapRect.
        func point(_ p: Point2D) -> CGPoint {
            let ll = zone.unproject(p)
            let c = CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon)
            if let snapshot { return snapshot.point(for: c) }
            let m = MKMapPoint(c)
            return CGPoint(x: (m.x - rect.minX) / rect.width * size.width, y: (m.y - rect.minY) / rect.height * size.height)
        }
        let metersPerPoint = frame.widthM / size.width

        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            if let snapshot {
                snapshot.image.draw(at: .zero)
                // Fade the imagery so vectors stay readable, like the basemap opacity.
                UIColor(hex: 0xFAF7F2).withAlphaComponent(0.35).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            } else {
                UIColor(hex: 0xFAF7F2).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for f in doc.features where f.isVisible && f.nodes.count > 1 {
                let path = UIBezierPath()
                path.usesEvenOddFillRule = true   // area holes are subpaths
                for ring in f.ringFeatures where !ring.nodes.isEmpty {
                    path.move(to: point(ring.nodes[0].point))
                    for s in ring.segments {
                        if s.isCurve {
                            path.addCurve(to: point(s.p3), controlPoint1: point(s.c1), controlPoint2: point(s.c2))
                        } else {
                            path.addLine(to: point(s.p3))
                        }
                    }
                    if f.closesPath { path.close() }
                }
                let color = UIColor(hexString: f.colorHex)
                if f.kind == .area {
                    color.withAlphaComponent(f.isSymbolArea ? 1 : 0.35).setFill()
                    path.fill()
                    if f.isSymbolArea { continue }
                }
                if f.kind == .line, let casing = f.casingColorHex, let inner = f.innerWidthMM {
                    UIColor(hexString: casing).setStroke()
                    path.lineWidth = max(1.5, CGFloat(doc.project.sheet.groundMeters(forPaperMM: f.widthMM) / metersPerPoint))
                    path.stroke()
                    color.setStroke()
                    path.lineWidth = max(0.75, CGFloat(doc.project.sheet.groundMeters(forPaperMM: inner) / metersPerPoint))
                    path.stroke()
                    continue
                }
                color.setStroke()
                path.lineWidth = max(1, CGFloat(doc.project.sheet.groundMeters(forPaperMM: f.widthMM) / metersPerPoint))
                path.stroke()
            }
            for f in doc.features where f.isVisible && f.kind == .point {
                guard let node = f.nodes.first else { continue }
                let c = point(node.point)
                let k = doc.project.sheet.groundMeters(forPaperMM: 1) / metersPerPoint
                PointSymbolRenderer.draw(f.scaledPointElements, in: cg, mmToUnits: k) { CGPoint(x: c.x + $0.x * k, y: c.y - $0.y * k) }
            }
            for s in doc.strokes {
                guard let first = s.points.first else { continue }
                let path = UIBezierPath()
                path.move(to: point(first))
                for p in s.points.dropFirst() { path.addLine(to: point(p)) }
                UIColor(hexString: s.colorHex).setStroke()
                path.lineWidth = max(1, CGFloat(doc.project.sheet.groundMeters(forPaperMM: s.widthMM) / metersPerPoint))
                path.stroke()
            }
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}
