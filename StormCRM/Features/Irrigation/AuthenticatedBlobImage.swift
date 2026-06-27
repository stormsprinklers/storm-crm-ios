import SwiftUI
import UIKit

enum BlobImageURL {
    static func resolved(_ storedUrl: String?, baseURL: String = AppConfig.apiBaseURL) -> URL? {
        guard let storedUrl, !storedUrl.isEmpty else { return nil }
        if storedUrl.contains("blob.vercel-storage.com"),
           let pathname = URL(string: storedUrl)?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
           !pathname.isEmpty {
            var components = URLComponents(string: baseURL + "/api/blob")!
            components.queryItems = [URLQueryItem(name: "pathname", value: pathname)]
            return components.url
        }
        if storedUrl.hasPrefix("/") {
            return URL(string: baseURL + storedUrl)
        }
        return URL(string: storedUrl)
    }

    static func needsAuthentication(_ storedUrl: String?) -> Bool {
        guard let storedUrl else { return false }
        return storedUrl.contains("blob.vercel-storage.com") || storedUrl.hasPrefix("/api/blob")
    }
}

struct AuthenticatedBlobImage: View {
    @EnvironmentObject private var env: AppEnvironment
    let urlString: String?
    var contentMode: ContentMode = .fit
    var onImageLoaded: ((CGSize) -> Void)?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                placeholder("Could not load image")
            } else {
                ProgressView()
            }
        }
        .task(id: urlString) { await load() }
    }

    private func placeholder(_ text: String) -> some View {
        ZStack {
            StormTheme.ice.opacity(0.3)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(8)
        }
    }

    private func load() async {
        image = nil
        failed = false
        guard let urlString, let url = BlobImageURL.resolved(urlString) else {
            failed = true
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if BlobImageURL.needsAuthentication(urlString),
           let token = env.tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let uiImage = UIImage(data: data) else {
                failed = true
                return
            }
            image = uiImage
            onImageLoaded?(uiImage.size)
        } catch {
            failed = true
        }
    }
}

struct EmployeeAvatar: View {
    @EnvironmentObject private var env: AppEnvironment
    let person: NamedColor
    var size: CGFloat = 32

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                initialsCircle
                    .overlay { ProgressView().scaleEffect(0.55) }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: person.photoUrl) { await loadPhoto() }
    }

    private var initialsCircle: some View {
        Circle()
            .fill(Color(hex: person.color) ?? StormTheme.sky)
            .overlay {
                Text(person.initials)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    private func loadPhoto() async {
        image = nil
        guard let photoUrl = person.photoUrl, !photoUrl.isEmpty,
              let url = BlobImageURL.resolved(photoUrl) else {
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if BlobImageURL.needsAuthentication(photoUrl),
           let token = env.tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let uiImage = UIImage(data: data) else {
                return
            }
            image = uiImage
        } catch {
            return
        }
    }
}

private extension NamedColor {
    var initials: String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map { String($0) }
            .joined()
            .uppercased()
    }
}
