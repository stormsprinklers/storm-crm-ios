import SwiftUI

/// Full-screen sheet: drag a rectangle over the aerial image to zoom/crop into that region.
/// Reports a normalized crop rectangle (0..1) relative to the displayed image.
struct IrrigationAerialCropView: View {
    let imageUrl: String
    let isBusy: Bool
    let onApply: (AerialCropRect) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var naturalImageSize = CGSize(width: 4, height: 3)
    @State private var startNorm: CGPoint?
    @State private var currentNorm: CGPoint?

    private var hasSelection: Bool {
        guard let s = startNorm, let c = currentNorm else { return false }
        return abs(c.x - s.x) > 0.03 && abs(c.y - s.y) > 0.03
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let layout = MapImageLayout(containerSize: geo.size, imageSize: naturalImageSize)
                ZStack {
                    Color.black.ignoresSafeArea()

                    AuthenticatedBlobImage(urlString: imageUrl, contentMode: .fit) { size in
                        if size.width > 0, size.height > 0 { naturalImageSize = size }
                    }

                    if let rect = selectionRect(in: layout) {
                        Rectangle()
                            .strokeBorder(Color.white, lineWidth: 2)
                            .background(Color.white.opacity(0.12))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }

                    if isBusy {
                        ProgressView("Zooming in…")
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !isBusy else { return }
                            let display = layout.displayRect
                            guard display.width > 0, display.height > 0 else { return }
                            if startNorm == nil {
                                startNorm = normalized(value.startLocation, in: display)
                            }
                            currentNorm = normalized(value.location, in: display)
                        }
                )
            }
            .navigationTitle("Zoom into area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isBusy)
                }
                ToolbarItem(placement: .principal) {
                    Text("Drag to select the area")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if startNorm != nil {
                        Button("Clear") {
                            startNorm = nil
                            currentNorm = nil
                        }
                        .disabled(isBusy)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zoom in") { apply() }
                        .disabled(!hasSelection || isBusy)
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
    }

    private func normalized(_ point: CGPoint, in display: CGRect) -> CGPoint {
        CGPoint(
            x: min(1, max(0, (point.x - display.minX) / display.width)),
            y: min(1, max(0, (point.y - display.minY) / display.height))
        )
    }

    private func selectionRect(in layout: MapImageLayout) -> CGRect? {
        guard let s = startNorm, let c = currentNorm else { return nil }
        let display = layout.displayRect
        guard display.width > 0, display.height > 0 else { return nil }
        let minX = display.minX + min(s.x, c.x) * display.width
        let minY = display.minY + min(s.y, c.y) * display.height
        let width = abs(c.x - s.x) * display.width
        let height = abs(c.y - s.y) * display.height
        guard width > 1, height > 1 else { return nil }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func apply() {
        guard let s = startNorm, let c = currentNorm else { return }
        let x = min(s.x, c.x)
        let y = min(s.y, c.y)
        let w = abs(c.x - s.x)
        let h = abs(c.y - s.y)
        guard w > 0.03, h > 0.03 else { return }
        onApply(AerialCropRect(x: Double(x), y: Double(y), width: Double(w), height: Double(h)))
    }
}
