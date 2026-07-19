import CoreLocation
import PhotosUI
import SwiftUI

private struct CapturedPhotoDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct VisitAttachmentsSection: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var uploadQueue = MediaUploadQueue.shared
    let visitId: String
    @State private var attachments: [AttachmentDTO] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var error: String?
    @State private var capturedDraft: CapturedPhotoDraft?
    @State private var showAnnotation = false
    @State private var showUploadOptions = false

    private var pendingUploadCount: Int {
        uploadQueue.pendingCount(for: visitId)
    }

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Attachments", systemImage: "paperclip")
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
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
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { file in
                            VStack {
                                if file.mimeType.hasPrefix("image/") {
                                    AuthenticatedBlobImage(urlString: file.blobUrl, contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Image(systemName: "doc.fill")
                                        .frame(width: 80, height: 80)
                                }
                                Text(file.fileName).font(.caption2).lineLimit(1)
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
                capturedDraft = CapturedPhotoDraft(image: image)
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
        .task { await load() }
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
        do {
            attachments = try await env.apiClient.get(path: APIPath.visitAttachments(visitId))
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func handlePickerItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { return }
            capturedDraft = CapturedPhotoDraft(image: image)
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
            try uploadQueue.enqueueVisitPhoto(visitId: visitId, data: data, fileName: fileName)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PartsRunSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let visitId: String
    var onComplete: (() async -> Void)?

    @State private var suppliers: [PartsRunOptionDTO] = []
    @State private var error: String?
    @State private var isLoading = true
    @State private var selectingId: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Finding the nearest suppliers…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if suppliers.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "shippingbox")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(error ?? "No suppliers found nearby.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(StormSecondaryButtonStyle())
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(suppliers) { supplier in
                            Button {
                                Task { await selectSupplier(supplier) }
                            } label: {
                                supplierRow(supplier)
                            }
                            .disabled(selectingId != nil)
                        }
                    }
                }
            }
            .navigationTitle("Parts run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func supplierRow(_ supplier: PartsRunOptionDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(titleLine(for: supplier))
                    .font(.headline)
                    .foregroundStyle(StormTheme.navy)
                if let address = supplier.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let miles = supplier.driveDistanceMiles {
                        Text(String(format: "%.1f mi", miles))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if supplier.isOpenNow == false {
                        Text("Closed now")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if supplier.isOpenNow == true {
                        Text("Open now")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(StormTheme.success)
                    }
                }
            }
            Spacer()
            if selectingId == supplier.id {
                ProgressView()
            } else if let minutes = supplier.driveMinutes {
                VStack(spacing: 0) {
                    Text(driveTimeValueLabel(minutes))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(StormTheme.sky)
                    Text(driveTimeUnitLabel(minutes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func driveTimeValueLabel(_ minutes: Int) -> String {
        if minutes >= 120 {
            let hours = Double(minutes) / 60.0
            return hours >= 10 ? String(format: "%.0f", hours) : String(format: "%.1f", hours)
        }
        return "\(minutes)"
    }

    private func driveTimeUnitLabel(_ minutes: Int) -> String {
        if minutes >= 120 { return "hrs" }
        return minutes == 1 ? "min" : "mins"
    }

    /// e.g. "Sprinkler World, Salt Lake City"
    private func titleLine(for supplier: PartsRunOptionDTO) -> String {
        if let city = supplier.city, !city.isEmpty {
            return "\(supplier.name), \(city)"
        }
        return supplier.name
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let location = await env.location.awaitLocation(timeout: 12) else {
            suppliers = []
            switch env.location.authorizationStatus {
            case .denied, .restricted:
                error = "Turn on Location access for Radar so we can rank suppliers from where you are."
            default:
                error = "Couldn't get your GPS location. Try again outdoors or check Location permission."
            }
            return
        }

        let query = [
            URLQueryItem(name: "originLat", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "originLng", value: String(location.coordinate.longitude)),
        ]

        do {
            let response: PartsRunGetResponse = try await env.apiClient.get(
                path: APIPath.visitPartsRun(visitId),
                query: query
            )
            // Always rank by drive time. Open/closed is shown as a badge — never bury nearby
            // closed stores behind far-away open ones.
            suppliers = (response.options ?? []).sorted(by: Self.nearerSupplier)
            if suppliers.isEmpty {
                error = response.message ?? "No suppliers found nearby."
            }
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private static func nearerSupplier(_ lhs: PartsRunOptionDTO, _ rhs: PartsRunOptionDTO) -> Bool {
        switch (lhs.driveMinutes, rhs.driveMinutes) {
        case let (l?, r?):
            if l != r { return l < r }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }
        switch (lhs.driveDistanceMiles, rhs.driveDistanceMiles) {
        case let (l?, r?):
            if l != r { return l < r }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func selectSupplier(_ supplier: PartsRunOptionDTO) async {
        selectingId = supplier.id
        defer { selectingId = nil }
        struct Body: Encodable { let supplierId: String }
        do {
            let response: PartsRunPostResponse = try await env.apiClient.post(
                path: APIPath.visitPartsRun(visitId),
                body: Body(supplierId: supplier.id)
            )
            if response.paused == true {
                await onComplete?()
            }
            let urlString = response.mapsUrl ?? supplier.mapsUrl
            if let urlString, let maps = URL(string: urlString) {
                #if canImport(UIKit)
                await UIApplication.shared.open(maps)
                #endif
            }
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
