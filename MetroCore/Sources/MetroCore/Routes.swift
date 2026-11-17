import Foundation

/// Parada de una ruta: estación y metros recorridos desde el principio.
public struct RouteStop: Equatable, Sendable {
    public let estacionID: String
    public let chainage: Double
}

/// Recorrido continuo de una línea en un sentido, con las distancias
/// acumuladas y la posición de sus estaciones. Sirve para colocar trenes.
public struct RouteGeometry: Sendable {
    public let ruta: Ruta
    public let puntos: [PuntoVia]
    /// `cumulative[i]` = metros desde el principio hasta `puntos[i]`.
    public let cumulative: [Double]
    /// Estaciones de la línea, ordenadas por distancia recorrida.
    public let stops: [RouteStop]

    private let chainageByStation: [String: Double]

    /// Distancia máxima de una estación a la ruta para considerarla parada suya.
    public static let stationTolerance = 60.0

    public init?(ruta: Ruta, red: Red) {
        var viasByID: [String: Via] = [:]
        for via in red.vias {
            viasByID[via.id] = via
        }

        var puntos: [PuntoVia] = []
        for tramo in ruta.tramos {
            guard let via = viasByID[tramo.via] else {
                continue
            }
            let ordered = tramo.inv ? Array(via.puntos.reversed()) : via.puntos
            for punto in ordered {
                if let last = puntos.last, Geo.distance(from: last.geo, to: punto.geo) < 0.05 {
                    continue
                }
                puntos.append(punto)
            }
        }
        guard puntos.count >= 2 else {
            return nil
        }

        var cumulative: [Double] = []
        cumulative.reserveCapacity(puntos.count)
        var total = 0.0
        for i in puntos.indices {
            if i > 0 {
                total += Geo.distance(from: puntos[i - 1].geo, to: puntos[i].geo)
            }
            cumulative.append(total)
        }

        self.ruta = ruta
        self.puntos = puntos
        self.cumulative = cumulative

        var stops: [RouteStop] = []
        var byStation: [String: Double] = [:]
        for estacion in red.estaciones {
            if !estacion.lineas.isEmpty, !estacion.lineas.contains(ruta.linea) {
                continue
            }
            guard let hit = RouteGeometry.project(estacion.geo, onto: puntos, cumulative: cumulative),
                  hit.distance <= RouteGeometry.stationTolerance
            else {
                continue
            }
            stops.append(RouteStop(estacionID: estacion.id, chainage: hit.chainage))
            byStation[estacion.id] = hit.chainage
        }
        stops.sort { $0.chainage < $1.chainage }
        self.stops = stops
        self.chainageByStation = byStation
    }

    public var length: Double {
        cumulative.last ?? 0
    }

    public func chainage(ofStation id: String) -> Double? {
        chainageByStation[id]
    }

    /// Última parada antes de `chainage` (sin contar las que están a menos de 1 m).
    public func stop(before chainage: Double) -> RouteStop? {
        stops.last { $0.chainage < chainage - 1 }
    }

    /// Proyecta un punto sobre la ruta.
    public func project(_ point: GeoPoint) -> (distance: Double, chainage: Double)? {
        RouteGeometry.project(point, onto: puntos, cumulative: cumulative)
    }

    /// Punto de la ruta a `chainage` metros del principio, con sus cotas.
    public func point(at chainage: Double) -> PuntoVia {
        let (segment, t) = locate(chainage)
        return puntos[segment].interpolated(to: puntos[segment + 1], t: t)
    }

    /// Rumbo de avance en grados (0 = norte, 90 = este).
    public func bearing(at chainage: Double) -> Double {
        var (segment, _) = locate(chainage)
        while segment < puntos.count - 2,
              Geo.distance(from: puntos[segment].geo, to: puntos[segment + 1].geo) < 0.01 {
            segment += 1
        }
        return Geo.bearing(from: puntos[segment].geo, to: puntos[segment + 1].geo)
    }

    private func locate(_ chainage: Double) -> (segment: Int, t: Double) {
        let clamped = min(max(chainage, 0), length)
        var low = 0
        var high = puntos.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if cumulative[middle] <= clamped {
                low = middle
            } else {
                high = middle
            }
        }
        let span = cumulative[low + 1] - cumulative[low]
        return (low, span > 1e-9 ? (clamped - cumulative[low]) / span : 0)
    }

    private static func project(
        _ point: GeoPoint,
        onto puntos: [PuntoVia],
        cumulative: [Double]
    ) -> (distance: Double, chainage: Double)? {
        guard puntos.count >= 2 else {
            return nil
        }
        let frame = LocalFrame(origin: point)
        var bestDistance = Double.greatestFiniteMagnitude
        var bestChainage = 0.0
        var a = frame.plane(lon: puntos[0].lon, lat: puntos[0].lat)
        for i in 1..<puntos.count {
            let b = frame.plane(lon: puntos[i].lon, lat: puntos[i].lat)
            let ab = b - a
            let lengthSquared = ab.dot(ab)
            var t = 0.0
            if lengthSquared > 1e-12 {
                // El punto buscado es el origen del sistema local.
                t = min(max(-(a.dot(ab)) / lengthSquared, 0), 1)
            }
            let distance = (a + ab * t).length
            if distance < bestDistance {
                bestDistance = distance
                bestChainage = cumulative[i - 1] + (cumulative[i] - cumulative[i - 1]) * t
            }
            a = b
        }
        return (bestDistance, bestChainage)
    }
}
