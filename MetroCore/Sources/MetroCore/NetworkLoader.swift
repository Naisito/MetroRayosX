import Foundation

public enum NetworkLoader {
    public static func decode(_ json: Data) throws -> Red {
        try JSONDecoder().decode(Red.self, from: json)
    }

    /// Lee `metro.json` y, si existe, la rejilla de relieve que tiene al lado.
    public static func load(jsonURL: URL, relieveURL: URL?) throws -> MetroModel {
        let red = try decode(try Data(contentsOf: jsonURL))
        var terrain: Terrain?
        if let info = red.relieve, let relieveURL = relieveURL,
           let data = try? Data(contentsOf: relieveURL) {
            terrain = try Terrain(info: info, data: data)
        }
        return MetroModel(red: red, terrain: terrain)
    }
}

/// Punto de la red más cercano a una posición.
public struct NearestTrack: Equatable, Sendable {
    public let viaIndex: Int
    /// Distancia horizontal en metros.
    public let distance: Double
    public let segment: Int
    public let t: Double
    /// Punto interpolado sobre la vía, con sus cotas.
    public let point: PuntoVia
    /// Metros recorridos desde el principio de la vía.
    public let chainage: Double
}

public struct BocaCercana: Equatable, Sendable, Identifiable {
    public let estacion: Estacion
    public let boca: Boca
    public let distance: Double

    public var id: String {
        "\(estacion.id)|\(boca.lat)|\(boca.lon)"
    }
}

/// Lo que el panel del mapa enseña sobre una posición.
public struct PositionSummary: Equatable, Sendable {
    public let estacion: Estacion?
    public let distanciaEstacion: Double?
    public let via: NearestTrack?
    /// Cota del suelo donde pisa el usuario.
    public let cotaSuelo: Double?
    /// Metros entre el suelo donde pisa el usuario y el carril más cercano.
    public let profundidad: Double?
    /// `true` si la cota del carril sale de una estimación y no de una medida.
    public let profundidadEstimada: Bool
}

/// Tramo de vía que se dibuja como una sola malla.
public struct ChunkKey: Hashable, Sendable {
    public let via: Int
    public let chunk: Int

    public init(via: Int, chunk: Int) {
        self.via = via
        self.chunk = chunk
    }
}

public struct SceneChunk: Equatable, Sendable {
    public let key: ChunkKey
    public let puntos: [PuntoVia]
    /// Metros desde el principio de la vía hasta el primer punto del tramo.
    public let startChainage: Double
    /// Distancia del usuario al punto más cercano del tramo.
    public let distance: Double
}

/// La red con sus índices: es lo que usan el mapa y la escena AR.
public final class MetroModel: @unchecked Sendable {
    public let red: Red
    public let terrain: Terrain?
    public let index: SpatialIndex
    public let rutas: [RouteGeometry]

    /// `viaChainage[v][i]` = metros desde el principio de la vía `v` hasta su punto `i`.
    private let viaChainage: [[Double]]
    private let stationIndexByStop: [String: Int]
    private let lineColors: [String: String]

    public init(red: Red, terrain: Terrain?) {
        self.red = red
        self.terrain = terrain
        self.index = SpatialIndex(vias: red.vias)

        var chainages: [[Double]] = []
        chainages.reserveCapacity(red.vias.count)
        for via in red.vias {
            var cumulative: [Double] = []
            cumulative.reserveCapacity(via.puntos.count)
            var total = 0.0
            for i in via.puntos.indices {
                if i > 0 {
                    total += Geo.distance(from: via.puntos[i - 1].geo, to: via.puntos[i].geo)
                }
                cumulative.append(total)
            }
            chainages.append(cumulative)
        }
        viaChainage = chainages

        var byStop: [String: Int] = [:]
        for (i, estacion) in red.estaciones.enumerated() {
            byStop[estacion.id] = i
            for parada in estacion.paradas {
                byStop[parada] = i
            }
        }
        stationIndexByStop = byStop

        var colors: [String: String] = [:]
        for linea in red.lineas {
            colors[linea.id] = linea.color
        }
        lineColors = colors

        rutas = red.rutas.compactMap { RouteGeometry(ruta: $0, red: red) }
    }

    // MARK: - Vías

    /// Vía más cercana a `point`, o `nil` si no hay ninguna a menos de `maxDistance`.
    public func nearestTrack(to point: GeoPoint, maxDistance: Double = 500) -> NearestTrack? {
        let frame = LocalFrame(origin: point)
        var best: NearestTrack?
        for viaIndex in index.candidates(near: point, radius: maxDistance) {
            let via = red.vias[viaIndex]
            let polyline = Polyline(points: via.puntos.map { frame.plane(lon: $0.lon, lat: $0.lat) })
            guard let hit = polyline.nearest(to: .zero), hit.distance <= maxDistance else {
                continue
            }
            if best == nil || hit.distance < best!.distance {
                let a = via.puntos[hit.segment]
                let b = via.puntos[min(hit.segment + 1, via.puntos.count - 1)]
                let cumulative = viaChainage[viaIndex]
                let chainageA = cumulative[hit.segment]
                let chainageB = cumulative[min(hit.segment + 1, cumulative.count - 1)]
                best = NearestTrack(
                    viaIndex: viaIndex,
                    distance: hit.distance,
                    segment: hit.segment,
                    t: hit.t,
                    point: a.interpolated(to: b, t: hit.t),
                    chainage: chainageA + (chainageB - chainageA) * hit.t
                )
            }
        }
        return best
    }

    /// Tramos de vía con algún punto a menos de `radius` metros de `point`.
    public func chunks(near point: GeoPoint, radius: Double, pointsPerChunk: Int = 20) -> [SceneChunk] {
        let frame = LocalFrame(origin: point)
        let step = max(pointsPerChunk, 2)
        var result: [SceneChunk] = []
        for viaIndex in index.candidates(near: point, radius: radius) {
            let puntos = red.vias[viaIndex].puntos
            guard puntos.count >= 2 else {
                continue
            }
            var start = 0
            var chunk = 0
            while start < puntos.count - 1 {
                let end = min(start + step, puntos.count - 1)
                var nearest = Double.greatestFiniteMagnitude
                for i in start...end {
                    nearest = min(nearest, frame.plane(lon: puntos[i].lon, lat: puntos[i].lat).length)
                }
                if nearest <= radius {
                    result.append(
                        SceneChunk(
                            key: ChunkKey(via: viaIndex, chunk: chunk),
                            puntos: Array(puntos[start...end]),
                            startChainage: viaChainage[viaIndex][start],
                            distance: nearest
                        )
                    )
                }
                start = end
                chunk += 1
            }
        }
        return result
    }

    /// Color `#rrggbb` de una vía: el de su primera línea.
    public func colorHex(of via: Via) -> String {
        for linea in via.lineas {
            if let color = lineColors[linea] {
                return color
            }
        }
        return "#ff7a00"
    }

    public func colorHex(ofLine id: String?) -> String {
        guard let id = id, let color = lineColors[id] else {
            return "#ff7a00"
        }
        return color
    }

    // MARK: - Suelo

    /// Cota del suelo en `point`: la rejilla de relieve y, fuera de ella,
    /// la del punto de vía más cercano.
    public func groundElevation(at point: GeoPoint) -> Double? {
        if let elevation = terrain?.elevation(at: point) {
            return elevation
        }
        return nearestTrack(to: point, maxDistance: 600)?.point.cotaSuelo
    }

    // MARK: - Estaciones

    public func station(forStop stopID: String) -> Estacion? {
        stationIndexByStop[stopID].map { red.estaciones[$0] }
    }

    public func nearestStation(to point: GeoPoint) -> (estacion: Estacion, distance: Double)? {
        var best: (estacion: Estacion, distance: Double)?
        for estacion in red.estaciones {
            let distance = Geo.distance(from: point, to: estacion.geo)
            if best == nil || distance < best!.distance {
                best = (estacion, distance)
            }
        }
        return best
    }

    /// Estaciones a menos de `radius` metros, de la más cercana a la más lejana.
    public func stations(near point: GeoPoint, radius: Double) -> [(estacion: Estacion, distance: Double)] {
        red.estaciones
            .map { (estacion: $0, distance: Geo.distance(from: point, to: $0.geo)) }
            .filter { $0.distance <= radius }
            .sorted { $0.distance < $1.distance }
    }

    /// Las `count` bocas más cercanas, para el botón «Estoy en esta boca».
    public func nearestBocas(to point: GeoPoint, count: Int = 3, maxDistance: Double = 400) -> [BocaCercana] {
        var all: [BocaCercana] = []
        for estacion in red.estaciones {
            for boca in estacion.bocas {
                let distance = Geo.distance(from: point, to: boca.geo)
                if distance <= maxDistance {
                    all.append(BocaCercana(estacion: estacion, boca: boca, distance: distance))
                }
            }
        }
        all.sort { $0.distance < $1.distance }
        return Array(all.prefix(max(count, 0)))
    }

    // MARK: - Resumen

    public func summary(at point: GeoPoint) -> PositionSummary {
        let station = nearestStation(to: point)
        let track = nearestTrack(to: point)
        let ground = groundElevation(at: point)
        var depth: Double?
        if let track = track, let ground = ground {
            depth = ground - track.point.cotaCarril
        }
        return PositionSummary(
            estacion: station?.estacion,
            distanciaEstacion: station?.distance,
            via: track,
            cotaSuelo: ground,
            profundidad: depth,
            profundidadEstimada: station?.estacion.origenCota == .estimado
        )
    }
}
