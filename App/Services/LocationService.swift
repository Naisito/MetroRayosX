import Combine
import CoreLocation
import Foundation

/// Posición, precisión y rumbo del iPhone con `CLLocationManager`.
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var reducedAccuracy = false
    @Published private(set) var location: CLLocation?
    @Published private(set) var heading: CLHeading?

    private let manager = CLLocationManager()
    private var updating = false
    private var lastLocationLog = Date.distantPast
    private var lastHeadingLog = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 1
        manager.activityType = .fitness
    }

    /// Pide permiso si hace falta y empieza a recibir posición y rumbo.
    func start() {
        refreshAuthorization()
        switch authorization {
        case .notDetermined:
            AppLog.shared.write("Pidiendo permiso de ubicación", category: "gps")
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        default:
            break
        }
    }

    /// Rumbo respecto al norte verdadero si está disponible; si no, el magnético.
    var headingDegrees: Double? {
        guard let heading = heading, heading.headingAccuracy >= 0 else {
            return nil
        }
        return heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
    }

    var headingIsTrueNorth: Bool {
        (heading?.trueHeading ?? -1) >= 0
    }

    var authorizationText: String {
        switch authorization {
        case .notDetermined:
            return "sin decidir"
        case .restricted:
            return "restringido"
        case .denied:
            return "denegado"
        case .authorizedAlways:
            return "siempre"
        case .authorizedWhenInUse:
            return "al usar la app"
        @unknown default:
            return "desconocido"
        }
    }

    private func refreshAuthorization() {
        authorization = manager.authorizationStatus
        reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
    }

    private func beginUpdates() {
        guard !updating else {
            return
        }
        updating = true
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        } else {
            AppLog.shared.write("Este dispositivo no tiene brújula", category: "gps")
        }
        AppLog.shared.write("Recibiendo posición y rumbo", category: "gps")
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAuthorization()
        AppLog.shared.write(
            "Permiso de ubicación: \(authorizationText), precisión \(reducedAccuracy ? "aproximada" : "exacta")",
            category: "gps"
        )
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            beginUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else {
            return
        }
        location = latest

        // Una línea cada 5 s basta para seguir la sesión sin llenar el registro.
        let now = Date()
        if now.timeIntervalSince(lastLocationLog) >= 5 {
            lastLocationLog = now
            AppLog.shared.write(
                String(
                    format: "lat=%.6f lon=%.6f ±%.1fm alt=%.1fm ±%.1fm",
                    latest.coordinate.latitude,
                    latest.coordinate.longitude,
                    latest.horizontalAccuracy,
                    latest.altitude,
                    latest.verticalAccuracy
                ),
                category: "gps"
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading

        let now = Date()
        if now.timeIntervalSince(lastHeadingLog) >= 10 {
            lastHeadingLog = now
            AppLog.shared.write(
                String(
                    format: "rumbo verdadero=%.1f magnético=%.1f ±%.1f",
                    newHeading.trueHeading,
                    newHeading.magneticHeading,
                    newHeading.headingAccuracy
                ),
                category: "gps"
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        AppLog.shared.write(
            "Error de ubicación: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)",
            category: "gps"
        )
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
