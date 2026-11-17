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

/// Punto del plano horizontal de la escena, en metros.
/// Convención de ejes del proyecto: x = este, z = sur (−z = norte).
public struct Vec2: Equatable, Sendable {
    public var x: Double
    public var z: Double

    public init(x: Double, z: Double) {
        self.x = x
        self.z = z
    }

    public static let zero = Vec2(x: 0, z: 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 {
        Vec2(x: a.x + b.x, z: a.z + b.z)
    }

    public static func - (a: Vec2, b: Vec2) -> Vec2 {
        Vec2(x: a.x - b.x, z: a.z - b.z)
    }

    public static func * (a: Vec2, k: Double) -> Vec2 {
        Vec2(x: a.x * k, z: a.z * k)
    }

    public var length: Double {
        (x * x + z * z).squareRoot()
    }

    public func distance(to other: Vec2) -> Double {
        (self - other).length
    }

    public func dot(_ other: Vec2) -> Double {
        x * other.x + z * other.z
    }

    /// Componente vertical del producto vectorial en el plano (x, z).
    public func cross(_ other: Vec2) -> Double {
        x * other.z - z * other.x
    }

    public var normalized: Vec2 {
        let l = length
        return l > 1e-12 ? Vec2(x: x / l, z: z / l) : Vec2(x: 1, z: 0)
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

    /// Rumbo en grados (0 = norte, 90 = este) para ir de `a` a `b`.
    public static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let offset = localOffset(of: b, from: a)
        let degrees = atan2(offset.east, offset.north) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}

/// Sistema de metros locales alrededor de un origen geográfico, con los ejes
/// de la escena: x = este, z = sur. Es el único sitio donde se cambia el signo
/// del norte.
public struct LocalFrame: Equatable, Sendable {
    public let origin: GeoPoint
    private let metersPerDegreeLat: Double
    private let metersPerDegreeLon: Double

    public init(origin: GeoPoint) {
        self.origin = origin
        metersPerDegreeLat = Geo.earthRadius * .pi / 180
        metersPerDegreeLon = Geo.earthRadius * .pi / 180 * cos(origin.latitude * .pi / 180)
    }

    /// De coordenadas geográficas al plano de la escena (x = este, z = −norte).
    public func plane(_ point: GeoPoint) -> Vec2 {
        Vec2(
            x: (point.longitude - origin.longitude) * metersPerDegreeLon,
            z: -(point.latitude - origin.latitude) * metersPerDegreeLat
        )
    }

    public func plane(lon: Double, lat: Double) -> Vec2 {
        Vec2(
            x: (lon - origin.longitude) * metersPerDegreeLon,
            z: -(lat - origin.latitude) * metersPerDegreeLat
        )
    }

    /// Del plano de la escena a coordenadas geográficas.
    public func geo(_ point: Vec2) -> GeoPoint {
        GeoPoint(
            latitude: origin.latitude - point.z / metersPerDegreeLat,
            longitude: origin.longitude + point.x / metersPerDegreeLon
        )
    }
}

/// Resultado de proyectar un punto sobre una polilínea.
public struct PolylineHit: Equatable, Sendable {
    /// Distancia del punto a la polilínea.
    public let distance: Double
    /// Metros recorridos desde el principio de la polilínea hasta el punto más cercano.
    public let chainage: Double
    /// Índice del segmento (entre `points[segment]` y `points[segment + 1]`).
    public let segment: Int
    /// Posición dentro del segmento, de 0 a 1.
    public let t: Double
    public let point: Vec2
}

/// Polilínea plana con distancias acumuladas.
public struct Polyline: Equatable, Sendable {
    public let points: [Vec2]
    /// `cumulative[i]` = metros desde el principio hasta `points[i]`.
    public let cumulative: [Double]

    public init(points: [Vec2]) {
        self.points = points
        var cumulative: [Double] = []
        cumulative.reserveCapacity(points.count)
        var total = 0.0
        for index in points.indices {
            if index > 0 {
                total += points[index].distance(to: points[index - 1])
            }
            cumulative.append(total)
        }
        self.cumulative = cumulative
    }

    public var length: Double {
        cumulative.last ?? 0
    }

    /// Punto de la polilínea más cercano a `target`. `nil` si está vacía.
    public func nearest(to target: Vec2) -> PolylineHit? {
        guard !points.isEmpty else {
            return nil
        }
        if points.count == 1 {
            return PolylineHit(
                distance: points[0].distance(to: target),
                chainage: 0,
                segment: 0,
                t: 0,
                point: points[0]
            )
        }
        var best: PolylineHit?
        for index in 0..<(points.count - 1) {
            let a = points[index]
            let b = points[index + 1]
            let ab = b - a
            let lengthSquared = ab.dot(ab)
            var t = 0.0
            if lengthSquared > 1e-12 {
                t = min(max((target - a).dot(ab) / lengthSquared, 0), 1)
            }
            let projected = a + ab * t
            let distance = projected.distance(to: target)
            if best == nil || distance < best!.distance {
                best = PolylineHit(
                    distance: distance,
                    chainage: cumulative[index] + (cumulative[index + 1] - cumulative[index]) * t,
                    segment: index,
                    t: t,
                    point: projected
                )
            }
        }
        return best
    }

    /// Segmento y posición dentro de él para una distancia recorrida.
    public func locate(chainage: Double) -> (segment: Int, t: Double) {
        guard points.count >= 2 else {
            return (0, 0)
        }
        let clamped = min(max(chainage, 0), length)
        // Búsqueda binaria del último punto con distancia acumulada <= clamped.
        var low = 0
        var high = points.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if cumulative[middle] <= clamped {
                low = middle
            } else {
                high = middle
            }
        }
        let span = cumulative[low + 1] - cumulative[low]
        let t = span > 1e-12 ? (clamped - cumulative[low]) / span : 0
        return (low, t)
    }

    public func point(at chainage: Double) -> Vec2 {
        guard let first = points.first else {
            return .zero
        }
        guard points.count >= 2 else {
            return first
        }
        let (segment, t) = locate(chainage: chainage)
        return points[segment] + (points[segment + 1] - points[segment]) * t
    }

    /// Dirección de avance (vector unitario) en una distancia recorrida.
    public func direction(at chainage: Double) -> Vec2 {
        guard points.count >= 2 else {
            return Vec2(x: 1, z: 0)
        }
        var (segment, _) = locate(chainage: chainage)
        // Evita segmentos de longitud cero.
        while segment < points.count - 2, points[segment + 1].distance(to: points[segment]) < 1e-9 {
            segment += 1
        }
        return (points[segment + 1] - points[segment]).normalized
    }
}
