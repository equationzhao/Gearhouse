import SwiftUI
import UIKit

struct NativeZoomableImage: UIViewRepresentable {
    let image: UIImage
    let accessibilityLabel: String
    let accessibilityIdentifier: String

    func makeUIView(context: Context) -> NativeZoomImageScrollView {
        NativeZoomImageScrollView()
    }

    func updateUIView(_ view: NativeZoomImageScrollView, context: Context) {
        view.accessibilityLabel = accessibilityLabel
        view.accessibilityIdentifier = accessibilityIdentifier
        view.installImage(image)
    }
}

final class NativeZoomImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var fittedSize = CGSize.zero
    private var fittingImage = false
    private let maximumFactor: CGFloat = 6

    init() {
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .black
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        delaysContentTouches = false
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoomAtTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        isAccessibilityElement = true
        accessibilityTraits = [.image, .adjustable]
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "放大", target: self, selector: #selector(increaseZoom)),
            UIAccessibilityCustomAction(name: "缩小", target: self, selector: #selector(decreaseZoom)),
            UIAccessibilityCustomAction(name: "还原大小", target: self, selector: #selector(resetZoom))
        ]
    }

    required init?(coder: NSCoder) { nil }

    override var accessibilityFrame: CGRect {
        get {
            let visible = imageView.convert(imageView.bounds, to: self).intersection(bounds)
            guard imageView.image != nil, !visible.isNull, !visible.isEmpty else { return super.accessibilityFrame }
            return UIAccessibility.convertToScreenCoordinates(visible, in: self)
        }
        set { super.accessibilityFrame = newValue }
    }

    func installImage(_ image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        fittedSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !fittingImage, let image = imageView.image,
              image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        if fittedSize != bounds.size {
            fittingImage = true
            fittedSize = bounds.size
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            minimumZoomScale = min(1, scale)
            maximumZoomScale = max(1, scale * maximumFactor)
            setZoomScale(1, animated: false)
            imageView.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size
            minimumZoomScale = scale
            maximumZoomScale = scale * maximumFactor
            setZoomScale(scale, animated: false)
            updateCenterInsets()
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
            fittingImage = false
        }
        updateCenterInsets()
        updateZoomValue()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !fittingImage else { return }
        updateCenterInsets()
        updateZoomValue()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            guard zoomScale > minimumZoomScale * 1.01 else { return false }
            let velocity = panGestureRecognizer.velocity(in: self)
            if abs(velocity.x) > abs(velocity.y) {
                let left = -contentInset.left
                let right = max(left, contentSize.width - bounds.width + contentInset.right)
                // A new outward gesture can turn the page; an active image pan never switches owners.
                if velocity.x > 0 && contentOffset.x <= left + 1 { return false }
                if velocity.x < 0 && contentOffset.x >= right - 1 { return false }
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    private func updateCenterInsets() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let next = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != next { contentInset = next }
    }

    private func updateZoomValue() {
        guard minimumZoomScale > 0 else { return }
        accessibilityValue = "\(Int((zoomScale / minimumZoomScale * 100).rounded()))%"
    }

    private func zoomImage(to factor: CGFloat, at point: CGPoint? = nil) {
        guard let image = imageView.image, minimumZoomScale > 0 else { return }
        let target = minimumZoomScale * min(maximumFactor, max(1, factor))
        if target <= minimumZoomScale * 1.01 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let center = point ?? imageView.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: self)
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        let origin = CGPoint(x: max(0, min(image.size.width - size.width, center.x - size.width / 2)),
                             y: max(0, min(image.size.height - size.height, center.y - size.height / 2)))
        zoom(to: CGRect(origin: origin, size: size), animated: true)
    }

    @objc private func toggleZoomAtTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: imageView)
        guard imageView.bounds.contains(point) else { return }
        zoomImage(to: zoomScale > minimumZoomScale * 1.01 ? 1 : 3, at: point)
    }

    @objc private func increaseZoom() -> Bool {
        zoomImage(to: zoomScale / max(minimumZoomScale, 0.001) * 1.5)
        return true
    }

    @objc private func decreaseZoom() -> Bool {
        zoomImage(to: zoomScale / max(minimumZoomScale, 0.001) / 1.5)
        return true
    }

    @objc private func resetZoom() -> Bool { zoomImage(to: 1); return true }
    override func accessibilityIncrement() { _ = increaseZoom() }
    override func accessibilityDecrement() { _ = decreaseZoom() }
    override func accessibilityActivate() -> Bool {
        zoomImage(to: zoomScale > minimumZoomScale * 1.01 ? 1 : 3)
        return true
    }
}
