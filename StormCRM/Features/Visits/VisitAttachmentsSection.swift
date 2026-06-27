import PhotosUI
import SwiftUI

struct VisitAttachmentsSection: View {
    @EnvironmentObject private var env: AppEnvironment
    let visitId: String
    @State private var attachments: [AttachmentDTO] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 8) {
                StormSectionHeader(title: "Attachments", systemImage: "paperclip")
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(attachments) { file in
                            VStack {
                                if file.mimeType.hasPrefix("image/"), let url = URL(string: file.blobUrl) {
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Image(systemName: "doc.fill")
                                        .frame(width: 80, height: 80)
                                }
                                Text(file.fileName).font(.caption2).lineLimit(1)
                            }
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Add photo", systemImage: "camera.fill")
                                .frame(width: 80, height: 80)
                                .background(StormTheme.ice.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func load() async {
        do {
            attachments = try await env.apiClient.get(path: APIPath.visitAttachments(visitId))
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
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
    @State private var suppliers: [PartsRunOptionDTO] = []
    @State private var error: String?
    @State private var mapsUrl: String?

    var body: some View {
        NavigationStack {
            List(suppliers) { supplier in
                Button {
                    Task { await selectSupplier(supplier.id) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(supplier.name).font(.headline)
                        if let address = supplier.address {
                            Text(address).font(.caption).foregroundStyle(.secondary)
                        }
                        if let miles = supplier.driveDistanceMiles {
                            Text(String(format: "%.1f mi", miles)).font(.caption2)
                        }
                    }
                }
            }
            .navigationTitle("Parts run")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay {
                if let mapsUrl, let url = URL(string: mapsUrl) {
                    Link("Open directions", destination: url)
                }
            }
            .task { await load() }
            if let error {
                Text(error).foregroundStyle(.red).padding()
            }
        }
    }

    private func load() async {
        do {
            let response: PartsRunGetResponse = try await env.apiClient.get(path: APIPath.visitPartsRun(visitId))
            suppliers = response.options ?? []
            if suppliers.isEmpty, let message = response.message {
                error = message
            }
        } catch {
            self.error = (error as? APIError)?.message
        }
    }

    private func selectSupplier(_ supplierId: String) async {
        struct Body: Encodable { let supplierId: String }
        do {
            let response: PartsRunPostResponse = try await env.apiClient.post(
                path: APIPath.visitPartsRun(visitId),
                body: Body(supplierId: supplierId)
            )
            mapsUrl = response.mapsUrl
            if let url = mapsUrl, let maps = URL(string: url) {
                #if canImport(UIKit)
                await UIApplication.shared.open(maps)
                #endif
            }
        } catch {
            self.error = (error as? APIError)?.message
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
