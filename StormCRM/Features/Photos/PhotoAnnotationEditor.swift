import SwiftUI
import UIKit

enum PhotoAnnotationTool: String, CaseIterable, Identifiable {
    case arrow
    case circle
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .circle: return "Circle"
        case .text: return "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .circle: return "circle"
        case .text: return "textformat"
        }
    }
}

private struct PhotoAnnotation: Identifiable, Equatable {
    enum Kind: Equatable {
        case arrow(start: CGPoint, end: CGPoint)
        case circle(center: CGPoint, radius: CGFloat)
        case text(position: CGPoint, text: String)
    }

    let id = UUID()
    var kind: Kind
    var color: Color = StormTheme.coral
}

/// SwiftUI canvas to annotate a photo. Returns a new UIImage; the caller keeps the original.
struct PhotoAnnotationEditor: View {
    let image: UIImage
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var tool: PhotoAnnotationTool = .arrow
    @State private var annotations: [PhotoAnnotation] = []
    @State private var draftStart: CGPoint?
    @State private var draftEnd: CGPoint?
    @State private var textDraft = ""
    @State private var textPosition: CGPoint?
    @State private var showTextPrompt = false
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let fitted = fittedImageRect(in: geo.size)
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: fitted.midX, y: fitted.midY)

                        Canvas { context, size in
                            for annotation in annotations {
                                draw(annotation, in: context, canvasSize: size, imageRect: fitted)
                            }
                            if let draftStart, let draftEnd {
                                let draft = PhotoAnnotation(
                                    kind: tool == .circle
                                        ? .circle(center: draftStart, radius: hypot(draftEnd.x - draftStart.x, draftEnd.y - draftStart.y))
                                        : .arrow(start: draftStart, end: draftEnd)
                                )
                                draw(draft, in: context, canvasSize: size, imageRect: fitted)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(imageRect: fitted))
                        .onTapGesture { location in
                            guard tool == .text else { return }
                            textPosition = location
                            showTextPrompt = true
                        }
                    }
                    .onAppear { canvasSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
                }

                toolBar
            }
            .background(Color.black.opacity(0.92).ignoresSafeArea())
            .navigationTitle("Annotate photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        let rendered = renderAnnotatedImage()
                        onDone(rendered)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo") {
                        _ = annotations.popLast()
                    }
                    .disabled(annotations.isEmpty)
                }
            }
            .alert("Add label", isPresented: $showTextPrompt) {
                TextField("Text", text: $textDraft)
                Button("Add") {
                    guard let textPosition, !textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    annotations.append(
                        PhotoAnnotation(kind: .text(position: textPosition, text: textDraft.trimmingCharacters(in: .whitespacesAndNewlines)))
                    )
                    textDraft = ""
                    self.textPosition = nil
                }
                Button("Cancel", role: .cancel) {
                    textDraft = ""
                    textPosition = nil
                }
            }
        }
    }

    private var toolBar: some View {
        HStack(spacing: 12) {
            ForEach(PhotoAnnotationTool.allCases) { item in
                Button {
                    tool = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.title3)
                        Text(item.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(tool == item ? StormTheme.sky.opacity(0.25) : Color.white.opacity(0.08))
                    .foregroundStyle(tool == item ? StormTheme.ice : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.55))
    }

    private func dragGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard tool != .text else { return }
                guard imageRect.contains(value.startLocation) || draftStart != nil else { return }
                if draftStart == nil { draftStart = value.startLocation }
                draftEnd = value.location
            }
            .onEnded { value in
                guard tool != .text else { return }
                guard imageRect.contains(value.startLocation) else {
                    draftStart = nil
                    draftEnd = nil
                    return
                }
                let start = value.startLocation
                let end = value.location
                switch tool {
                case .arrow:
                    annotations.append(PhotoAnnotation(kind: .arrow(start: start, end: end)))
                case .circle:
                    let radius = hypot(end.x - start.x, end.y - start.y)
                    annotations.append(PhotoAnnotation(kind: .circle(center: start, radius: max(radius, 8))))
                case .text:
                    break
                }
                draftStart = nil
                draftEnd = nil
            }
    }

    private func fittedImageRect(in container: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let imageAspect = image.size.width / image.size.height
        let containerAspect = container.width / container.height
        if imageAspect > containerAspect {
            let width = container.width
            let height = width / imageAspect
            let y = (container.height - height) / 2
            return CGRect(x: 0, y: y, width: width, height: height)
        } else {
            let height = container.height
            let width = height * imageAspect
            let x = (container.width - width) / 2
            return CGRect(x: x, y: 0, width: width, height: height)
        }
    }

    private func draw(_ annotation: PhotoAnnotation, in context: GraphicsContext, canvasSize: CGSize, imageRect: CGRect) {
        let uiColor = UIColor(annotation.color)
        switch annotation.kind {
        case .arrow(let start, let end):
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(annotation.color), lineWidth: 3)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength: CGFloat = 14
            let left = CGPoint(
                x: end.x - headLength * cos(angle - .pi / 6),
                y: end.y - headLength * sin(angle - .pi / 6)
            )
            let right = CGPoint(
                x: end.x - headLength * cos(angle + .pi / 6),
                y: end.y - headLength * sin(angle + .pi / 6)
            )
            var head = Path()
            head.move(to: end)
            head.addLine(to: left)
            head.move(to: end)
            head.addLine(to: right)
            context.stroke(head, with: .color(annotation.color), lineWidth: 3)
        case .circle(let center, let radius):
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(annotation.color), lineWidth: 3)
        case .text(let position, let text):
            context.draw(
                Text(text)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(annotation.color),
                at: position,
                anchor: .bottomLeading
            )
        }
        _ = uiColor
        _ = canvasSize
        _ = imageRect
    }

    private func renderAnnotatedImage() -> UIImage {
        let fitted = fittedImageRect(in: canvasSize)
        guard fitted.width > 0, fitted.height > 0 else { return image }

        let scaleX = image.size.width / fitted.width
        let scaleY = image.size.height / fitted.height

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let cg = ctx.cgContext

            for annotation in annotations {
                UIColor(annotation.color).setStroke()
                UIColor(annotation.color).setFill()
                cg.setLineWidth(3 * min(scaleX, scaleY))

                switch annotation.kind {
                case .arrow(let start, let end):
                    let s = CGPoint(x: (start.x - fitted.minX) * scaleX, y: (start.y - fitted.minY) * scaleY)
                    let e = CGPoint(x: (end.x - fitted.minX) * scaleX, y: (end.y - fitted.minY) * scaleY)
                    cg.move(to: s)
                    cg.addLine(to: e)
                    cg.strokePath()
                    let angle = atan2(e.y - s.y, e.x - s.x)
                    let headLength = 14 * min(scaleX, scaleY)
                    cg.move(to: e)
                    cg.addLine(to: CGPoint(x: e.x - headLength * cos(angle - .pi / 6), y: e.y - headLength * sin(angle - .pi / 6)))
                    cg.move(to: e)
                    cg.addLine(to: CGPoint(x: e.x - headLength * cos(angle + .pi / 6), y: e.y - headLength * sin(angle + .pi / 6)))
                    cg.strokePath()
                case .circle(let center, let radius):
                    let c = CGPoint(x: (center.x - fitted.minX) * scaleX, y: (center.y - fitted.minY) * scaleY)
                    let r = radius * min(scaleX, scaleY)
                    cg.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                case .text(let position, let text):
                    let p = CGPoint(x: (position.x - fitted.minX) * scaleX, y: (position.y - fitted.minY) * scaleY)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 18 * min(scaleX, scaleY)),
                        .foregroundColor: UIColor(annotation.color),
                    ]
                    (text as NSString).draw(at: p, withAttributes: attrs)
                }
            }
        }
    }
}
