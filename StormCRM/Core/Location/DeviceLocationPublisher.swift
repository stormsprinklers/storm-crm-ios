import CoreLocation
import Foundation
import UIKit

/// Always-on pings so office staff can locate signed-in iPads.
@MainActor
final class DeviceLocationPublisher: ObservableObject {
    @Published private(set) var isPublishing = false

    private weak var api: APIClient?
    private weak var locationManager: LocationManager?
    private var pollTask: Task<Void, Never>?
    private var lastPostedAt: Date?
    private var lastPostedCoordinate: CLLocationCoordinate2D?

    private let minInterval: TimeInterval = 45
    private let minDistanceMeters: CLLocationDistance = 80

    private let deviceIdKey = "storm.fieldDeviceId"

    var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceIdKey)
        return id
    }

    func configure(api: APIClient, location: LocationManager) {
        self.api = api
        self.locationManager = location
    }

    func start() {
        if isPublishing { return }
        isPublishing = true
        locationManager?.requestPermission()
        locationManager?.setFleetTracking(true)

        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isPublishing {
                await self.publishIfNeeded()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isPublishing = false
        lastPostedAt = nil
        lastPostedCoordinate = nil
        locationManager?.setFleetTracking(false)
    }

    private func publishIfNeeded() async {
        guard let api, let locationManager else { return }
        guard let location = locationManager.lastLocation ?? (await locationManager.awaitLocation(timeout: 8)) else {
            return
        }

        let now = Date()
        if let lastPostedAt, now.timeIntervalSince(lastPostedAt) < minInterval {
            if let last = lastPostedCoordinate {
                let prev = CLLocation(latitude: last.latitude, longitude: last.longitude)
                if location.distance(from: prev) < minDistanceMeters {
                    return
                }
            } else {
                return
            }
        }

        struct Body: Encodable {
            let deviceId: String
            let deviceName: String
            let lat: Double
            let lng: Double
            let heading: Double?
            let accuracyMeters: Double?
        }

        let heading = location.course >= 0 ? location.course : nil
        do {
            struct Ack: Decodable {
                let ok: Bool?
                let skipped: Bool?
            }
            let _: Ack = try await api.post(
                path: APIPath.mobileDeviceLocation,
                body: Body(
                    deviceId: deviceId,
                    deviceName: UIDevice.current.name,
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude,
                    heading: heading,
                    accuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
                )
            )
            lastPostedAt = now
            lastPostedCoordinate = location.coordinate
        } catch {
            // Keep trying on the next interval.
        }
    }
}
