import CoreLocation
import Foundation

/// Streams GPS while a visit is EN_ROUTE and posts pings to the CRM.
@MainActor
final class EnRouteLocationPublisher: ObservableObject {
    @Published private(set) var isPublishing = false
    @Published private(set) var lastError: String?

    private weak var api: APIClient?
    private weak var locationManager: LocationManager?
    private var visitId: String?
    private var pollTask: Task<Void, Never>?
    private var lastPostedAt: Date?
    private var lastPostedCoordinate: CLLocationCoordinate2D?

    private let minInterval: TimeInterval = 15
    private let minDistanceMeters: CLLocationDistance = 40

    func configure(api: APIClient, location: LocationManager) {
        self.api = api
        self.locationManager = location
    }

    func start(visitId: String) {
        if isPublishing, self.visitId == visitId { return }
        stop()
        self.visitId = visitId
        isPublishing = true
        lastError = nil
        locationManager?.requestPermission()
        locationManager?.setEnRouteTracking(true)

        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isPublishing, self.visitId == visitId {
                await self.publishIfNeeded()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isPublishing = false
        visitId = nil
        lastPostedAt = nil
        lastPostedCoordinate = nil
        locationManager?.setEnRouteTracking(false)
    }

    private func publishIfNeeded() async {
        guard let api, let visitId, let locationManager else { return }
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
            let lat: Double
            let lng: Double
            let heading: Double?
            let speedMps: Double?
        }

        let heading = location.course >= 0 ? location.course : nil
        let speed = location.speed >= 0 ? location.speed : nil
        do {
            struct Ack: Decodable {
                let ok: Bool?
                let skipped: Bool?
            }
            let _: Ack = try await api.post(
                path: APIPath.visitLocation(visitId),
                body: Body(
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude,
                    heading: heading,
                    speedMps: speed
                )
            )
            lastPostedAt = now
            lastPostedCoordinate = location.coordinate
            lastError = nil
        } catch {
            lastError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
