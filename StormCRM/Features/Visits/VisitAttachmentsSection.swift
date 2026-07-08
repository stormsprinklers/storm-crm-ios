import PhotosUI
import SwiftUI

struct VisitAttachmentsSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visitId: String
    @State private var attachments: [AttachmentDTO] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isUploading = false
    @State private var error: String?

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Attachments", systemImage: "paperclip")
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
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
                        .disabled(isUploading)

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            AttachmentAddTile(title: "Library", systemImage: "photo.on.rectangle")
                        }
                        .disabled(isUploading)

                        if isUploading {
                            ProgressView()
                                .frame(width: 80, height: 80)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker { image in
                Task { await uploadImageData(image.attachmentJPEGData()) }
            }
            .ignoresSafeArea()
        }
        .task { await load() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                await uploadPickerItem(item)
                pickerItem = nil
            }
        }
    }

    private func load() async {
        do {
            attachments = try await env.apiClient.get(path: APIPath.visitAttachments(visitId))
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func uploadPickerItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            await uploadImageData(data)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func uploadImageData(_ data: Data?) async {
        guard let data, !data.isEmpty else {
            error = "Could not read photo"
            return
        }
        isUploading = true
        error = nil
        defer { isUploading = false }
        do {
            let fileName = "photo-\(Int(Date().timeIntervalSince1970)).jpg"
            _ = try await env.apiClient.uploadMultipart(
                path: APIPath.visitAttachments(visitId),
                fileData: data,
                fileName: fileName,
                mimeType: "image/jpeg"
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
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
    @State private var usedUserLocation = false
    @State private var locationNote: String?
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
                        if let locationNote {
                            Text(locationNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
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
                        Section {
                            ForEach(suppliers) { supplier in
                                Button {
                                    Task { await selectSupplier(supplier) }
                                } label: {
                                    supplierRow(supplier)
                                }
                                .disabled(selectingId != nil)
                            }
                        } footer: {
                            VStack(alignment: .leading, spacing: 4) {
                                if let locationNote {
                                    Text(locationNote)
                                }
                                Text(usedUserLocation
                                     ? "Sorted by drive time from your current location. Tap a supplier to pause your timer and open directions."
                                     : "Sorted by drive time from the job site. Tap a supplier to pause your timer and open directions.")
                            }
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
                    Text("\(minutes)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(StormTheme.sky)
                    Text(minutes == 1 ? "min" : "mins")
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

        let location = await env.location.awaitLocation(timeout: 12)
        if location != nil {
            locationNote = nil
        } else {
            switch env.location.authorizationStatus {
            case .denied, .restricted:
                locationNote = "Location access is off — distances use the job site instead of your current position."
            default:
                locationNote = "Couldn't get GPS — distances may be less accurate."
            }
        }

        var query: [URLQueryItem] = []
        if let location {
            query = [
                URLQueryItem(name: "originLat", value: String(location.coordinate.latitude)),
                URLQueryItem(name: "originLng", value: String(location.coordinate.longitude)),
            ]
        }

        do {
            let response: PartsRunGetResponse = try await env.apiClient.get(
                path: APIPath.visitPartsRun(visitId),
                query: query
            )
            suppliers = response.options ?? []
            usedUserLocation = response.usedUserLocation ?? false
            if suppliers.isEmpty {
                error = response.message ?? "No suppliers found nearby."
            }
        } catch {
            self.error = (error as? APIError)?.message
        }
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
