import MapKit
import UIKit

/// GPS position marker for surveying: dot, accuracy circle (true size on the map), radar pulse, and a heading
/// cone that follows the direction the iPad faces. Used as the `MKUserLocation` annotation view.
final class UserRadarView: MKAnnotationView {
    static let reuseID = "cakra.radar"

    private let accuracyLayer = CAShapeLayer()
    private let pulseLayer = CAShapeLayer()
    private let coneLayer = CAGradientLayer()
    private let coneMask = CAShapeLayer()
    private let coneEdge = CAShapeLayer()
    private let dotLayer = CAShapeLayer()

    private let sky = UIColor(hex: 0x315E85)
    private let skyLight = UIColor(hex: 0x4A90D9)

    /// Accuracy radius on screen (pt).
    var accuracyRadius: CGFloat = 0 { didSet { if abs(oldValue - accuracyRadius) > 0.5 { layoutRadar() } } }
    /// Heading relative to the screen (degrees clockwise from the top of the screen); nil = no compass.
    var screenHeading: Double? { didSet { updateCone() } }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        clipsToBounds = false
        canShowCallout = false
        isUserInteractionEnabled = false
        zPriority = .max

        accuracyLayer.fillColor = skyLight.withAlphaComponent(0.12).cgColor
        accuracyLayer.strokeColor = skyLight.withAlphaComponent(0.55).cgColor
        accuracyLayer.lineWidth = 1

        pulseLayer.fillColor = UIColor.clear.cgColor
        pulseLayer.strokeColor = skyLight.cgColor
        pulseLayer.lineWidth = 2

        coneLayer.type = .radial
        coneLayer.colors = [sky.withAlphaComponent(0.75).cgColor, skyLight.withAlphaComponent(0.2).cgColor]
        coneEdge.fillColor = UIColor.clear.cgColor
        coneEdge.strokeColor = sky.withAlphaComponent(0.6).cgColor
        coneEdge.lineWidth = 1
        coneLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        coneLayer.endPoint = CGPoint(x: 1, y: 1)
        coneLayer.mask = coneMask

        dotLayer.fillColor = sky.cgColor
        dotLayer.strokeColor = UIColor.white.cgColor
        dotLayer.lineWidth = 3
        dotLayer.shadowColor = UIColor.black.cgColor
        dotLayer.shadowOpacity = 0.25
        dotLayer.shadowRadius = 2
        dotLayer.shadowOffset = CGSize(width: 0, height: 1)

        coneLayer.addSublayer(coneEdge)
        for l in [accuracyLayer, pulseLayer, coneLayer, dotLayer] as [CALayer] { layer.addSublayer(l) }
        layoutRadar()
        updateCone()
        startPulse()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        startPulse()
    }

    private var center0: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func circle(_ r: CGFloat) -> CGPath {
        UIBezierPath(arcCenter: .zero, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
    }

    private func layoutRadar() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let c = center0
        accuracyLayer.position = c
        accuracyLayer.path = circle(max(accuracyRadius, 0))
        accuracyLayer.isHidden = accuracyRadius < 10
        pulseLayer.position = c
        pulseLayer.path = circle(1)
        dotLayer.position = c
        dotLayer.path = circle(8)

        let r: CGFloat = 70
        // bounds + position (not frame): frame is undefined once the layer is rotated.
        coneLayer.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        coneLayer.position = c
        let wedge = UIBezierPath()
        wedge.move(to: CGPoint(x: r, y: r))
        // ±30° cone facing up (−y axis); rotated via the transform.
        wedge.addArc(withCenter: CGPoint(x: r, y: r), radius: r, startAngle: -.pi / 2 - .pi / 6, endAngle: -.pi / 2 + .pi / 6, clockwise: true)
        wedge.close()
        coneMask.path = wedge.cgPath
        coneEdge.frame = coneLayer.bounds
        coneEdge.path = wedge.cgPath
        CATransaction.commit()
        startPulse()
    }

    private func updateCone() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let h = screenHeading {
            coneLayer.isHidden = false
            coneLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(h * .pi / 180)))
        } else {
            coneLayer.isHidden = true
        }
        CATransaction.commit()
    }

    /// The radar ring grows from the dot to the accuracy circle (at least 36 pt), then fades. Repeats every 2 seconds.
    private func startPulse() {
        pulseLayer.removeAllAnimations()
        let target = max(accuracyRadius, 36)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 8
        scale.toValue = target
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 2
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulseLayer.lineWidth = 2 / target
        pulseLayer.add(group, forKey: "radar")
    }
}
