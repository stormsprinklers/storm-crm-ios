import PhotosUI
import SwiftUI

private struct CustomerCapturedPhotoDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct CustomerAttachmentsSection: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var uploadQueue = MediaUploadQueue.shared
    let customerId: String

    @State private var attachments: [AttachmentDTO] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var error: String?
    @State private var capturedDraft: CustomerCapturedPhotoDraft?
    @State private var showAnnotation = false
    @State private var showUploadOptions = false
    @State private var isLoading = false

    private var pendingUploadCount: Int {
        uploadQueue.pendingCount(forCustomerId: customerId)
    }

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Attachments", systemImage: "paperclip")

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if isLoading && attachments.isEmpty {
                    ProgressView("Loading attachments…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if attachments.isEmpty && pendingUploadCount == 0 {
                    Text("No attachments yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if pendingUploadCount > 0 || uploadQueue.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("\(pendingUploadCount) photo(s) uploading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { file in
                            VStack(spacing: 4) {
                                if file.mimeType.hasPrefix("image/") {
                                    AuthenticatedBlobImage(urlString: file.blobUrl, contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Image(systemName: "doc.fill")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, height: 80)
                                        .background(StormTheme.ice.opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Text(file.fileName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 80)
                            }
                        }

                        AttachmentAddTile(title: "Take photo", systemImage: "camera.fill") {
                            showCamera = true
                        }

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            AttachmentAddTile(title: "Library", systemImage: "photo.on.rectangle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker { image in
                capturedDraft = CustomerCapturedPhotoDraft(image: image)
                showUploadOptions = true
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Photo captured", isPresented: $showUploadOptions, titleVisibility: .visible) {
            Button("Upload as-is") {
                if let draft = capturedDraft {
                    queueUpload(image: draft.image)
                }
                capturedDraft = nil
            }
            Button("Annotate first") {
                showAnnotation = true
            }
            Button("Cancel", role: .cancel) {
                capturedDraft = nil
            }
        } message: {
            Text("Optionally add arrows, circles, or labels before uploading.")
        }
        .fullScreenCover(isPresented: $showAnnotation) {
            if let draft = capturedDraft {
                PhotoAnnotationEditor(
                    image: draft.image,
                    onDone: { annotated in
                        queueUpload(image: annotated)
                        capturedDraft = nil
                        showUploadOptions = false
                    },
                    onCancel: {
                        showUploadOptions = true
                    }
                )
            }
        }
        .task(id: customerId) { await load() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                await handlePickerItem(item)
                pickerItem = nil
            }
        }
        .onChange(of: uploadQueue.items.count) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        guard env.offlineSync.isOnline else { return }
        isLoading = attachments.isEmpty
        defer { isLoading = false }
        do {
            attachments = try await env.apiClient.get(path: APIPath.customerAttachments(customerId))
            error = nil
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func handlePickerItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { return }
            capturedDraft = CustomerCapturedPhotoDraft(image: image)
            showUploadOptions = true
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func queueUpload(image: UIImage) {
        error = nil
        guard let data = image.attachmentJPEGData() else {
            error = "Could not read photo"
            return
        }
        let fileName = "photo-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try uploadQueue.enqueueCustomerPhoto(customerId: customerId, data: data, fileName: fileName)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
