import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func refreshLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }
        manager.requestLocation()
        manager.startUpdatingLocation()
    }

    /// Waits for a fresh GPS fix (used for On my way ETA).
    func awaitLocation(timeout: TimeInterval = 10) async -> CLLocation? {
        if let last = lastLocation, abs(last.timestamp.timeIntervalSinceNow) < 30 {
            return last
        }

        requestPermission()
        refreshLocation()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let location = lastLocation { return location }
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                return nil
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        manager.stopUpdatingLocation()
        return lastLocation
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            lastLocation = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Best-effort GPS for en-route ETA
    }
}
