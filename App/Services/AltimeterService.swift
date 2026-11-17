import Combine
import CoreMotion
import Foundation

/// Barómetro del iPhone (`CMAltimeter`) para el modo medición: da el
/// desnivel respecto al punto donde se pulsa Inicio.
final class AltimeterService: ObservableObject {
    /// Metros respecto al inicio de la medición (negativo = se ha bajado).
    @Published private(set) var relativeAltitude: Double?
    @Published private(set) var isRunning = false
    @Published private(set) var errorText: String?

    private let altimeter = CMAltimeter()

    var isAvailable: Bool {
        CMAltimeter.isRelativeAltitudeAvailable()
    }

    func start() {
        guard isAvailable else {
            errorText = "Este iPhone no tiene barómetro."
            return
        }
        if CMAltimeter.authorizationStatus() == .denied {
            errorText = "Sin permiso de movimiento. Actívalo en Ajustes > Privacidad y seguridad > Movimiento y actividad física."
            return
        }
        errorText = nil
        relativeAltitude = nil
        isRunning = true
        AppLog.shared.write("Barómetro: inicio de medición", category: "medir")
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self = self else {
                return
            }
            if let error = error {
                self.errorText = "Error del barómetro: \(error.localizedDescription)"
                AppLog.shared.write("Barómetro: \(error)", category: "medir")
                self.stop()
                return
            }
            if let data = data {
                self.relativeAltitude = data.relativeAltitude.doubleValue
            }
        }
    }

    func stop() {
        guard isRunning else {
            return
        }
        altimeter.stopRelativeAltitudeUpdates()
        isRunning = false
    }
}
