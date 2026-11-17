import ARKit
import Combine
import Foundation
import MetroCore

/// Registro de la app. Escribe en `Documents/metro-rayosx.log` y guarda las
/// últimas líneas para enseñarlas en pantalla. Se puede llamar desde cualquier hilo.
final class AppLog: ObservableObject {
    static let shared = AppLog()

    private static let maxRecent = 200

    @Published private(set) var recent: [String]
    let fileURL: URL

    private let file: FileLog

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appendingPathComponent("metro-rayosx.log")
        let file = FileLog(fileURL: url)
        self.fileURL = url
        self.file = file
        self.recent = file.tail(lines: AppLog.maxRecent)
    }

    func write(_ message: String, category: String = "app") {
        let line = file.write(message, category: category)
        if Thread.isMainThread {
            remember(line)
        } else {
            DispatchQueue.main.async {
                self.remember(line)
            }
        }
    }

    func clear() {
        file.clear()
        recent = []
        write("Registro vaciado")
    }

    func logSessionStart() {
        write("=== Sesión nueva: Metro Rayos X \(AppInfo.version), build \(AppInfo.build), commit \(AppInfo.commit) ===")
        write("Dispositivo \(AppInfo.deviceModel), iOS \(AppInfo.systemVersion)")
        write(
            "ARKit: worldTracking=\(ARWorldTrackingConfiguration.isSupported) "
                + "geoTracking=\(ARGeoTrackingConfiguration.isSupported)",
            category: "ar"
        )
    }

    private func remember(_ line: String) {
        recent.append(line)
        if recent.count > AppLog.maxRecent {
            recent.removeFirst(recent.count - AppLog.maxRecent)
        }
    }
}
