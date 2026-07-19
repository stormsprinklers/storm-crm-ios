import Foundation
import SwiftUI

/// Builds non-interactive Google Static Maps / Street View Image URLs from Embed API URLs
/// returned by `/api/maps/embed` (same API key, still image instead of an iframe map).
enum GoogleMapsStaticImage {
    static func streetViewURL(fromEmbed embedURL: URL, width: Int = 640, height: Int = 400) -> URL? {
        if embedURL.path.contains("/maps/api/streetview") {
            return sized(embedURL, width: width, height: height)
        }

        guard let items = URLComponents(url: embedURL, resolvingAgainstBaseURL: false)?.queryItems,
              let key = value("key", in: items)
        else { return nil }

        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/streetview")
        var query: [URLQueryItem] = [
            URLQueryItem(name: "size", value: "\(min(width, 640))x\(min(height, 640))"),
            URLQueryItem(name: "key", value: key),
        ]

        if let location = value("location", in: items) ?? value("q", in: items) {
            query.append(URLQueryItem(name: "location", value: location))
        } else if let pano = value("pano", in: items) {
            query.append(URLQueryItem(name: "pano", value: pano))
        } else {
            return nil
        }

        if let heading = value("heading", in: items) {
            query.append(URLQueryItem(name: "heading", value: heading))
        }
        if let pitch = value("pitch", in: items) {
            query.append(URLQueryItem(name: "pitch", value: pitch))
        }
        if let fov = value("fov", in: items) {
            query.append(URLQueryItem(name: "fov", value: fov))
        }

        components?.queryItems = query
        return components?.url
    }

    static func mapURL(fromPlaceEmbed embedURL: URL, width: Int = 640, height: Int = 360) -> URL? {
        if embedURL.path.contains("/maps/api/staticmap") {
            return sized(embedURL, width: width, height: height)
        }

        guard let items = URLComponents(url: embedURL, resolvingAgainstBaseURL: false)?.queryItems,
              let key = value("key", in: items),
              let center = value("q", in: items) ?? value("center", in: items) ?? value("location", in: items)
        else { return nil }

        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")
        components?.queryItems = [
            URLQueryItem(name: "center", value: center),
            URLQueryItem(name: "zoom", value: "16"),
            URLQueryItem(name: "size", value: "\(min(width, 640))x\(min(height, 640))"),
            URLQueryItem(name: "scale", value: "2"),
            URLQueryItem(name: "maptype", value: "roadmap"),
            URLQueryItem(name: "markers", value: "color:red|\(center)"),
            URLQueryItem(name: "key", value: key),
        ]
        return components?.url
    }

    private static func value(_ name: String, in items: [URLQueryItem]) -> String? {
        items.first(where: { $0.name == name })?.value
    }

    private static func sized(_ url: URL, width: Int, height: Int) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "size" }
        items.append(URLQueryItem(name: "size", value: "\(min(width, 640))x\(min(height, 640))"))
        components.queryItems = items
        return components.url ?? url
    }
}

/// Displays a static Google Maps / Street View image (no WebKit, not interactive).
struct GoogleMapsStaticImageView: View {
    let url: URL
    var height: CGFloat = 220

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder(systemImage: "photo", text: "Preview unavailable")
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            @unknown default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func placeholder(systemImage: String, text: String) -> some View {
        ZStack {
            StormTheme.ice.opacity(0.35)
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(text)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
}
