import Foundation

/// Punto en coordenadas geográficas, en grados.
public struct GeoPoint: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Desplazamiento en metros respecto a un punto de referencia.
public struct LocalOffset: Equatable, Sendable {
    /// Metros hacia el este (negativo = oeste).
    public let east: Double
    /// Metros hacia el norte (negativo = sur).
    public let north: Double

    public init(east: Double, north: Double) {
        self.east = east
        self.north = north
    }

    public var distance: Double {
        (east * east + north * north).squareRoot()
    }
}

public enum Geo {
    /// Radio ecuatorial de WGS84, en metros.
    public static let earthRadius = 6_378_137.0

    /// Pasa un punto a metros locales alrededor de `reference`.
    /// Aproximación plana de PLAN.md: error menor de 1 m a varios kilómetros.
    public static func localOffset(of point: GeoPoint, from reference: GeoPoint) -> LocalOffset {
        let lat0 = reference.latitude * .pi / 180
        let dLat = (point.latitude - reference.latitude) * .pi / 180
        let dLon = (point.longitude - reference.longitude) * .pi / 180
        return LocalOffset(
            east: earthRadius * dLon * cos(lat0),
            north: earthRadius * dLat
        )
    }

    /// Distancia horizontal en metros entre dos puntos cercanos.
    public static func distance(from a: GeoPoint, to b: GeoPoint) -> Double {
        localOffset(of: b, from: a).distance
    }
}
