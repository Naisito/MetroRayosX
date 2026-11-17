import Foundation

/// Avisos al usuario (ver «Cuándo avisar al usuario» en PLAN.md).
public enum Advisory: String, Equatable, Sendable, CaseIterable {
    case sinPermiso
    case ubicacionAproximada
    case interior
    case gpsDebil
    case arLimitado
    case brujulaImprecisa
    case lejosDelMetro
    case sinTrenes

    public var mensaje: String {
        switch self {
        case .sinPermiso:
            return "Sin permiso de ubicación. Actívalo en Ajustes para colocar el túnel."
        case .ubicacionAproximada:
            return "La ubicación está en modo aproximado. Activa «Ubicación exacta» en Ajustes."
        case .interior:
            return "Parece que estás en interior. La app funciona en la calle, a cielo abierto."
        case .gpsDebil:
            return "Señal débil, acércate a una boca y ánclate."
        case .arLimitado:
            return "Mueve el móvil despacio y apunta a una zona con detalle."
        case .brujulaImprecisa:
            return "Aléjate de coches o estructuras metálicas."
        case .lejosDelMetro:
            return "No hay metro a menos de 400 m de aquí."
        case .sinTrenes:
            return "Sin conexión: los trenes en vivo no se actualizan."
        }
    }
}

public struct AdvisoryInput: Equatable, Sendable {
    public var hasLocationPermission = true
    public var reducedAccuracy = false
    /// Precisión horizontal del GPS en metros; `nil` si aún no hay posición.
    public var gpsAccuracy: Double?
    public var trackingLimited = false
    /// Precisión de la brújula en grados; `nil` si no hay rumbo.
    public var headingAccuracy: Double?
    /// `true` mientras la orientación del túnel depende de la brújula.
    public var dependsOnCompass = true
    /// `true` si el usuario se ha anclado en una boca: el GPS deja de importar tanto.
    public var anchored = false
    public var distanceToTrack: Double?
    public var trainsOffline = false

    public init() {}
}

public enum Advisories {
    public static let weakGPS = 20.0
    public static let indoorGPS = 50.0
    public static let badHeading = 25.0
    public static let farFromTrack = 400.0

    /// Avisos que aplican, del más importante al menos.
    public static func evaluate(_ input: AdvisoryInput) -> [Advisory] {
        var result: [Advisory] = []
        guard input.hasLocationPermission else {
            return [.sinPermiso]
        }
        if input.reducedAccuracy {
            result.append(.ubicacionAproximada)
        }
        if let accuracy = input.gpsAccuracy, !input.anchored {
            if accuracy < 0 || accuracy > indoorGPS {
                result.append(.interior)
            } else if accuracy > weakGPS {
                result.append(.gpsDebil)
            }
        }
        if input.trackingLimited {
            result.append(.arLimitado)
        }
        if input.dependsOnCompass, let heading = input.headingAccuracy, heading < 0 || heading > badHeading {
            result.append(.brujulaImprecisa)
        }
        if let distance = input.distanceToTrack, distance > farFromTrack {
            result.append(.lejosDelMetro)
        }
        if input.trainsOffline {
            result.append(.sinTrenes)
        }
        return result
    }
}
