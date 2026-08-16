import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var fleetTracking = false
    private var enRouteTracking = false

    private var isContinuous: Bool { fleetTracking || enRouteTracking }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 150
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }
        if authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func refreshLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }
        manager.requestLocation()
        if !isContinuous {
            manager.startUpdatingLocation()
        }
    }

    func setFleetTracking(_ enabled: Bool) {
        fleetTracking = enabled
        applyTrackingMode()
    }

    func setEnRouteTracking(_ enabled: Bool) {
        enRouteTracking = enabled
        applyTrackingMode()
    }

    /// Continuous GPS for live customer tracking while EN_ROUTE.
    func startContinuousUpdates(forBackground: Bool) {
        setEnRouteTracking(true)
        _ = forBackground
    }

    func stopContinuousUpdates() {
        setEnRouteTracking(false)
    }

    private func applyTrackingMode() {
        requestPermission()
        guard isContinuous else {
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            manager.stopUpdatingLocation()
            manager.stopMonitoringSignificantLocationChanges()
            return
        }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }

        if enRouteTracking {
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 25
            manager.pausesLocationUpdatesAutomatically = false
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 150
            manager.pausesLocationUpdatesAutomatically = true
        }

        let always = authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = always
        manager.showsBackgroundLocationIndicator = always && enRouteTracking
        manager.startUpdatingLocation()
        if always {
            manager.startMonitoringSignificantLocationChanges()
        }
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
        if !isContinuous {
            manager.stopUpdatingLocation()
        }
        return lastLocation
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                if isContinuous {
                    applyTrackingMode()
                } else {
                    manager.requestLocation()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            lastLocation = locations.last
            if !isContinuous {
                manager.stopUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Best-effort GPS for fleet tracking / en-route ETA
    }
}
