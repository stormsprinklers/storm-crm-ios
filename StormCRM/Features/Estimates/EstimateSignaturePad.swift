import SwiftUI
import UIKit

/// Finger-friendly signature capture for estimate approval on iPhone / iPad.
struct EstimateSignaturePad: UIViewRepresentable {
    @Binding var hasInk: Bool
    var controller: EstimateSignatureController

    func makeUIView(context: Context) -> SignatureCanvasView {
        let view = SignatureCanvasView()
        view.isExclusiveTouch = true
        view.onInkChanged = { hasInk in
            DispatchQueue.main.async {
                self.hasInk = hasInk
            }
        }
        controller.canvas = view
        return view
    }

    func updateUIView(_ uiView: SignatureCanvasView, context: Context) {
        controller.canvas = uiView
        uiView.onInkChanged = { hasInk in
            DispatchQueue.main.async {
                self.hasInk = hasInk
            }
        }
    }
}

@MainActor
final class EstimateSignatureController: ObservableObject {
    weak var canvas: SignatureCanvasView?

    var hasInk: Bool { canvas?.hasInk ?? false }

    func clear() {
        canvas?.clear()
    }

    func pngData() -> Data? {
        canvas?.pngData()
    }
}

final class SignatureCanvasView: UIView {
    var onInkChanged: ((Bool) -> Void)?

    private var strokes: [[CGPoint]] = []
    private var currentStroke: [CGPoint] = []
    private weak var enclosingScrollView: UIScrollView?
    private var restoredScrollEnabled: Bool?

    var hasInk: Bool { !strokes.isEmpty || currentStroke.count > 1 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
        isUserInteractionEnabled = true
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clear() {
        strokes = []
        currentStroke = []
        setNeedsDisplay()
        onInkChanged?(false)
    }

    func pngData() -> Data? {
        guard hasInk else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: bounds).fill()
            UIColor.black.setStroke()
            for stroke in strokes {
                drawStroke(stroke, lineWidth: 3.5)
            }
        }
        return image.pngData()
    }

    override func draw(_ rect: CGRect) {
        UIColor.black.setStroke()
        for stroke in strokes {
            drawStroke(stroke, lineWidth: 3.5)
        }
        if currentStroke.count > 1 {
            drawStroke(currentStroke, lineWidth: 3.5)
        }
    }

    private func drawStroke(_ stroke: [CGPoint], lineWidth: CGFloat) {
        guard stroke.count > 1 else { return }
        let path = UIBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: stroke[0])
        for point in stroke.dropFirst() {
            path.addLine(to: point)
        }
        path.stroke()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        disableEnclosingScroll()
        guard let point = touches.first?.location(in: self) else { return }
        currentStroke = [point]
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        currentStroke.append(point)
        setNeedsDisplay()
        onInkChanged?(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke()
        restoreEnclosingScroll()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke()
        restoreEnclosingScroll()
    }

    private func finishStroke() {
        if currentStroke.count > 1 {
            strokes.append(currentStroke)
        }
        currentStroke = []
        setNeedsDisplay()
        onInkChanged?(hasInk)
    }

    /// Keep the parent SwiftUI/UIKit ScrollView from stealing the drawing gesture.
    private func disableEnclosingScroll() {
        guard enclosingScrollView == nil else { return }
        var walker: UIView? = superview
        while let view = walker {
            if let scroll = view as? UIScrollView {
                enclosingScrollView = scroll
                restoredScrollEnabled = scroll.isScrollEnabled
                scroll.isScrollEnabled = false
                scroll.panGestureRecognizer.isEnabled = false
                return
            }
            walker = view.superview
        }
    }

    private func restoreEnclosingScroll() {
        guard let scroll = enclosingScrollView else { return }
        scroll.panGestureRecognizer.isEnabled = true
        scroll.isScrollEnabled = restoredScrollEnabled ?? true
        enclosingScrollView = nil
        restoredScrollEnabled = nil
    }
}
