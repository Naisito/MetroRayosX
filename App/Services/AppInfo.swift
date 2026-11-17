import UIKit

/// Datos de la versión instalada y del dispositivo, para la pantalla y el registro.
enum AppInfo {
    static var version: String {
        infoValue("CFBundleShortVersionString")
    }

    /// Número de ejecución de GitHub Actions que generó este .ipa.
    static var build: String {
        infoValue("CFBundleVersion")
    }

    static var commit: String {
        infoValue("GitCommit")
    }

    /// Identificador del modelo, por ejemplo "iPhone14,5".
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        var identifier = ""
        for child in mirror.children {
            guard let value = child.value as? Int8, value != 0 else {
                break
            }
            identifier.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "desconocido" : identifier
    }

    static var systemVersion: String {
        UIDevice.current.systemVersion
    }

    private static func infoValue(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? "?"
    }
}
