import CoreLocation
import Foundation

enum AppleMapsURL {
    /// Builds a turn-by-turn directions URL for Apple Maps, preferring coordinates when available.
    static func directionsURL(
        latitude: Double?,
        longitude: Double?,
        address: String?
    ) -> URL? {
        if let lat = latitude, let lng = longitude {
            return directionsURL(destination: "\(lat),\(lng)")
        }
        guard let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else {
            return nil
        }
        return directionsURL(destination: address)
    }

    /// Formats address parts into a single line suitable for maps and geocoding.
    static func formattedAddress(
        street: String?,
        city: String?,
        state: String?,
        zip: String?
    ) -> String? {
        let parts = [street, city, state, zip]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func formattedAddress(for visit: VisitDetailDTO) -> String? {
        if let address = formattedAddress(
            street: visit.address,
            city: visit.city,
            state: visit.state,
            zip: visit.zip
        ) {
            return address
        }
        if let property = visit.property {
            return formattedAddress(
                street: property.address,
                city: property.city,
                state: property.state,
                zip: property.zip
            )
        }
        return nil
    }

    private static func directionsURL(destination: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "daddr", value: destination)]
        return components.url
    }
}
