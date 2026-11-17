import Combine
import Foundation
import MetroCore

/// Descarga los feeds GTFS-Realtime del CTB cada 20 s mientras alguna
/// pantalla los necesita. El feed se regenera una vez por minuto; entre
/// lecturas los trenes se mueven solos porque su posición se calcula a partir
/// de las horas de llegada (ver `TrainLocator`).
final class RealtimeService: ObservableObject {
    static let tripUpdatesURL = URL(
        string: "https://ctb-gtfs-rt.s3.eu-south-2.amazonaws.com/metro-bilbao-trip-updates.pb"
    )!
    static let vehiclePositionsURL = URL(
        string: "https://ctb-gtfs-rt.s3.eu-south-2.amazonaws.com/metro-bilbao-vehicle-positions.pb"
    )!
    static let interval: TimeInterval = 20

    /// Última descarga correcta.
    @Published private(set) var lastSuccess: Date?
    /// `true` si las últimas descargas han fallado.
    @Published private(set) var offline = false

    private(set) var tripUpdates: [RTTripUpdate] = []
    private(set) var vehicles: [RTVehicle] = []

    private var clients = 0
    private var timer: Timer?
    private var failures = 0
    private var inFlight = false

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Una pantalla empieza a necesitar los trenes.
    func retain() {
        clients += 1
        guard timer == nil else {
            return
        }
        AppLog.shared.write("Trenes en vivo: empezando a descargar", category: "trenes")
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: RealtimeService.interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Una pantalla deja de necesitarlos.
    func release() {
        clients = max(clients - 1, 0)
        if clients == 0 {
            timer?.invalidate()
            timer = nil
            AppLog.shared.write("Trenes en vivo: parado", category: "trenes")
        }
    }

    /// `true` si hay datos lo bastante recientes como para dibujar trenes.
    var hasFreshData: Bool {
        guard let lastSuccess = lastSuccess else {
            return false
        }
        return Date().timeIntervalSince(lastSuccess) < 180
    }

    /// Trenes en circulación a la hora `now`.
    func trains(locator: TrainLocator, now: Date = Date()) -> [TrainPosition] {
        guard hasFreshData else {
            return []
        }
        return locator.locate(tripUpdates: tripUpdates, vehicles: vehicles, now: now)
    }

    private func poll() {
        guard !inFlight else {
            return
        }
        inFlight = true

        let group = DispatchGroup()
        let download = Download()

        fetch(RealtimeService.tripUpdatesURL, group: group) { data, error in
            download.updates = data
            download.error = download.error ?? error
        }
        fetch(RealtimeService.vehiclePositionsURL, group: group) { data, error in
            download.vehicles = data
            download.error = download.error ?? error
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else {
                return
            }
            self.inFlight = false
            guard let updatesData = download.updates else {
                self.fail(download.error ?? "sin datos")
                return
            }
            do {
                let updates = try GTFSRealtimeFeed(data: updatesData)
                // Las posiciones son un complemento: si fallan, se sigue sin ellas.
                let positions = download.vehicles.flatMap { try? GTFSRealtimeFeed(data: $0) }
                self.tripUpdates = updates.tripUpdates
                self.vehicles = positions?.vehicles ?? []
                if self.offline || self.lastSuccess == nil {
                    AppLog.shared.write(
                        "Feed recibido: \(updates.tripUpdates.count) viajes, \(self.vehicles.count) posiciones",
                        category: "trenes"
                    )
                }
                self.failures = 0
                self.offline = false
                self.lastSuccess = Date()
            } catch {
                self.fail("feed ilegible: \(error)")
            }
        }
    }

    /// Resultado de una ronda de descargas. Solo se toca en el hilo principal.
    private final class Download {
        var updates: Data?
        var vehicles: Data?
        var error: String?
    }

    /// Descarga `url` y llama a `completion` en el hilo principal con los
    /// datos o con el motivo del fallo.
    private func fetch(_ url: URL, group: DispatchGroup, completion: @escaping (Data?, String?) -> Void) {
        group.enter()
        let task = session.dataTask(with: url) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let failure = error?.localizedDescription ?? (status == 200 ? nil : "HTTP \(status)")
            DispatchQueue.main.async {
                if let data = data, failure == nil {
                    completion(data, nil)
                } else {
                    completion(nil, failure ?? "respuesta vacía")
                }
                group.leave()
            }
        }
        task.resume()
    }

    private func fail(_ reason: String) {
        failures += 1
        if failures == 1 || failures % 10 == 0 {
            AppLog.shared.write("Fallo al descargar el feed (\(failures)): \(reason)", category: "trenes")
        }
        if failures >= 2 {
            offline = true
        }
    }
}
