import Combine
import Foundation
import MetroCore

/// Graba GPS + poses AR en un JSON para reproducir una prueba de calle en
/// un test (`SessionReplay` en MetroCore) sin tener que volver a salir.
final class SessionRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var sampleCount = 0
    @Published private(set) var lastFile: URL?

    private var recording: SessionRecording?
    private var startDate = Date()

    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("sesiones", isDirectory: true)
    }

    /// Grabaciones guardadas, de la más reciente a la más antigua.
    static func savedFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func begin(mode: String, origin: GeoPoint) {
        startDate = Date()
        let formatter = ISO8601DateFormatter()
        recording = SessionRecording(
            inicio: formatter.string(from: startDate),
            dispositivo: "\(AppInfo.deviceModel), iOS \(AppInfo.systemVersion), build \(AppInfo.build)",
            modo: mode,
            origenLat: origin.latitude,
            origenLon: origin.longitude
        )
        sampleCount = 0
        isRecording = true
        AppLog.shared.write("Grabación de sesión iniciada (modo \(mode))", category: "sesion")
    }

    /// Añade una muestra. Los campos que no se conozcan se dejan a `nil`.
    func add(_ fill: (inout SessionSample) -> Void) {
        guard isRecording, recording != nil else {
            return
        }
        var sample = SessionSample(t: Date().timeIntervalSince(startDate))
        fill(&sample)
        recording?.muestras.append(sample)
        sampleCount += 1
    }

    /// Cierra la grabación y la guarda. Devuelve el fichero.
    @discardableResult
    func finish() -> URL? {
        guard isRecording, let recording = recording else {
            return nil
        }
        isRecording = false
        self.recording = nil

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "sesion-\(formatter.string(from: startDate)).json"
        let url = SessionRecorder.folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: SessionRecorder.folder, withIntermediateDirectories: true)
            try recording.encoded().write(to: url, options: .atomic)
            lastFile = url
            AppLog.shared.write(
                "Sesión guardada: \(name), \(recording.muestras.count) muestras",
                category: "sesion"
            )
            return url
        } catch {
            AppLog.shared.write("No se pudo guardar la sesión: \(error)", category: "sesion")
            return nil
        }
    }
}
