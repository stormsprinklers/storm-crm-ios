import SwiftUI
import UIKit

struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

extension UIImage {
    func attachmentJPEGData(compressionQuality: CGFloat = 0.85) -> Data? {
        jpegData(compressionQuality: compressionQuality)
    }
}

struct AttachmentAddTile: View {
    let title: String
    let systemImage: String
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    tileContent
                }
                .buttonStyle(.plain)
            } else {
                tileContent
            }
        }
    }

    private var tileContent: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(StormTheme.sky)
            Text(title)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(width: 80, height: 80)
        .background(StormTheme.ice.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
