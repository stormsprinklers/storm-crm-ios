import AVKit
import SwiftUI

struct MessageMediaGalleryView: View {
    let media: [MessageMediaDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(media) { item in
                if item.isVideo {
                    AuthenticatedVideoPlayer(urlString: item.blobUrl)
                        .frame(maxWidth: 240, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if item.isImage {
                    AuthenticatedBlobImage(urlString: item.blobUrl, contentMode: .fill)
                        .frame(maxWidth: 240, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Link(item.fileName ?? "Attachment", destination: blobURL(item.blobUrl) ?? URL(string: "about:blank")!)
                        .font(.caption)
                }
            }
        }
    }

    private func blobURL(_ stored: String) -> URL? {
        BlobImageURL.resolved(stored)
    }
}

struct AuthenticatedVideoPlayer: View {
    @EnvironmentObject private var env: AppEnvironment
    let urlString: String

    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else if failed {
                Text("Could not load video")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(StormTheme.ice.opacity(0.3))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: urlString) { await load() }
    }

    private func load() async {
        player = nil
        failed = false
        guard let url = BlobImageURL.resolved(urlString) else {
            failed = true
            return
        }

        var request = URLRequest(url: url)
        if BlobImageURL.needsAuthentication(urlString),
           let token = env.tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                failed = true
                return
            }
            let ext = urlString.lowercased().contains(".mov") ? "mov" : "mp4"
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try data.write(to: tempURL)
            player = AVPlayer(url: tempURL)
        } catch {
            failed = true
        }
    }
}
