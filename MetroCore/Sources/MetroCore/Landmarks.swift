import Foundation

/// Lugar con nombre, usado en la Fase 0 para comprobar la cobertura de geotracking.
public struct Landmark: Equatable, Sendable, Identifiable {
    public let name: String
    public let point: GeoPoint

    public var id: String { name }

    public init(name: String, point: GeoPoint) {
        self.name = name
        self.point = point
    }
}

/// Coordenadas aproximadas, suficientes para preguntar por la cobertura de una zona.
/// Las coordenadas exactas de las estaciones llegarán con `metro.json` en la Fase 1.
public enum Landmarks {
    public static let moyua = Landmark(
        name: "Moyua",
        point: GeoPoint(latitude: 43.2631, longitude: -2.9350)
    )

    public static let cascoViejo = Landmark(
        name: "Zazpikaleak/Casco Viejo",
        point: GeoPoint(latitude: 43.2600, longitude: -2.9222)
    )

    public static let geoTrackingProbes = [moyua, cascoViejo]
}
