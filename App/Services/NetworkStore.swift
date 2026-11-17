import Combine
import Foundation
import MetroCore

/// Carga `metro.json` y `relieve.bin` del paquete de la app.
final class NetworkStore: ObservableObject {
    enum State {
        case loading
        case ready(MetroModel)
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    private var started = false

    var model: MetroModel? {
        if case .ready(let model) = state {
            return model
        }
        return nil
    }

    var errorText: String? {
        if case .failed(let text) = state {
            return text
        }
        return nil
    }

    func load() {
        guard !started else {
            return
        }
        started = true
        let begin = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            let result: State
            do {
                guard let json = Bundle.main.url(forResource: "metro", withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let relieve = Bundle.main.url(forResource: "relieve", withExtension: "bin")
                let model = try NetworkLoader.load(jsonURL: json, relieveURL: relieve)
                result = .ready(model)
                let red = model.red
                AppLog.shared.write(
                    String(
                        format: "Red cargada en %.2f s: %d vías, %d rutas, %d estaciones, relieve %@, datos del %@",
                        Date().timeIntervalSince(begin),
                        red.vias.count,
                        model.rutas.count,
                        red.estaciones.count,
                        model.terrain == nil ? "NO" : "sí",
                        red.generado
                    ),
                    category: "datos"
                )
            } catch {
                result = .failed("No se pudieron cargar los datos del metro: \(error.localizedDescription)")
                AppLog.shared.write("Error al cargar la red: \(error)", category: "datos")
            }
            DispatchQueue.main.async {
                self.state = result
            }
        }
    }
}
