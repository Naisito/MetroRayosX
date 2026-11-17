import ARKit
import Combine
import CoreLocation
import MetroCore

/// Una pregunta a Apple: ¿hay geotracking de ARKit en este punto?
struct GeoTrackingCheck: Identifiable {
    enum State: Equatable {
        case checking
        case available
        case unavailable(reason: String?)
    }

    let name: String
    let point: GeoPoint
    var state: State

    var id: String { name }
}

/// Comprueba la cobertura de geotracking (Modo A del plan) en la posición
/// actual y en dos puntos del centro de Bilbao, y lo deja apuntado en el registro.
final class GeoTrackingProbe: ObservableObject {
    @Published private(set) var checks: [GeoTrackingCheck] = []

    let deviceSupported = ARGeoTrackingConfiguration.isSupported

    private var runID = UUID()

    var isRunning: Bool {
        checks.contains { $0.state == .checking }
    }

    func run(userLocation: CLLocation?) {
        guard !isRunning else {
            return
        }
        let currentRun = UUID()
        runID = currentRun

        var targets: [GeoTrackingCheck] = []
        if let userLocation = userLocation {
            let point = GeoPoint(
                latitude: userLocation.coordinate.latitude,
                longitude: userLocation.coordinate.longitude
            )
            targets.append(GeoTrackingCheck(name: "Tu posición", point: point, state: .checking))
        }
        for landmark in Landmarks.geoTrackingProbes {
            targets.append(GeoTrackingCheck(name: landmark.name, point: landmark.point, state: .checking))
        }
        checks = targets

        AppLog.shared.write(
            "Comprobando geotracking. Dispositivo compatible: \(deviceSupported ? "sí" : "no")",
            category: "geo"
        )
        if userLocation == nil {
            AppLog.shared.write("Sin posición todavía: solo se comprueban los puntos fijos", category: "geo")
        }

        for target in targets {
            let coordinate = CLLocationCoordinate2D(
                latitude: target.point.latitude,
                longitude: target.point.longitude
            )
            ARGeoTrackingConfiguration.checkAvailability(at: coordinate) { [weak self] available, error in
                DispatchQueue.main.async {
                    guard let self = self, self.runID == currentRun else {
                        return
                    }
                    self.finish(name: target.name, available: available, error: error)
                }
            }
        }

        // Sin conexión la respuesta puede no llegar nunca.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, self.runID == currentRun else {
                return
            }
            for check in self.checks where check.state == .checking {
                self.resolve(name: check.name, state: .unavailable(reason: "sin respuesta en 20 s"))
            }
        }
    }

    private func finish(name: String, available: Bool, error: Error?) {
        if available {
            resolve(name: name, state: .available)
            return
        }
        var reason: String?
        if let nsError = error as NSError? {
            reason = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        }
        resolve(name: name, state: .unavailable(reason: reason))
    }

    private func resolve(name: String, state: GeoTrackingCheck.State) {
        guard let index = checks.firstIndex(where: { $0.name == name }),
              checks[index].state == .checking
        else {
            return
        }
        checks[index].state = state

        let check = checks[index]
        let place = String(format: "%@ (%.5f, %.5f)", check.name, check.point.latitude, check.point.longitude)
        switch state {
        case .checking:
            break
        case .available:
            AppLog.shared.write("\(place): DISPONIBLE", category: "geo")
        case .unavailable(let reason):
            var message = place + ": NO DISPONIBLE"
            if let reason = reason {
                message += " — " + reason
            }
            AppLog.shared.write(message, category: "geo")
        }
    }
}
