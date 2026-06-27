import MapKit
import SwiftUI

struct JobMapView: View {
    let title: String
    let address: String?
    let latitude: Double?
    let longitude: Double?

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        StormCard {
            VStack(alignment: .leading, spacing: 10) {
                StormSectionHeader(title: "Job location", systemImage: "map")
                if let coordinate = coordinate {
                    Map(position: $position) {
                        Marker(title, coordinate: coordinate)
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onAppear {
                        position = .region(MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        ))
                    }
                } else if let address, !address.isEmpty {
                    Text(address).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("No address on file").font(.caption).foregroundStyle(.secondary)
                }

                if let url = directionsURL {
                    Link(destination: url) {
                        Label("Directions in Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(StormTheme.sky)
                }
            }
        }
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private var directionsURL: URL? {
        if let coordinate {
            return URL(string: "http://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)")
        }
        if let address, !address.isEmpty {
            let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
            return URL(string: "http://maps.apple.com/?daddr=\(encoded)")
        }
        return nil
    }
}
