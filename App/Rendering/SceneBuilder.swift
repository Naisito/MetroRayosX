import Foundation
import MetroCore
import RealityKit
import simd
import UIKit

/// Crea y recicla las entidades de RealityKit: túnel, estaciones, bocas,
/// trenes, rejilla y línea de profundidad.
///
/// Todo cuelga de `root` y va en coordenadas de la escena (x = este,
/// y = arriba, z = sur, en metros alrededor del origen de `SceneFrame`).
/// Quien coloca `root` en el mundo de ARKit es `ARExperience`.
@MainActor
final class SceneBuilder {
    /// Radio de dibujo, en metros.
    static let radius = 400.0
    /// Tramos que se construyen como mucho en cada imagen, para no dar tirones.
    static let chunksPerFrame = 5
    static let fadeBands = 4
    static let carLength: Float = 17.5
    static let carGap: Float = 0.6
    static let carsPerTrain = 4

    let root = Entity()
    let grid = GroundGrid()

    private let tracksNode = Entity()
    private let stationsNode = Entity()
    private let trainsNode = Entity()
    private let depthNode = Entity()

    private struct ChunkEntities {
        let parent: Entity
        var rails: ModelEntity?
        var bed: ModelEntity?
        var structure: ModelEntity?
        var band: Int
        let colorHex: String
    }

    private var frame: SceneFrame?
    private var chunks: [ChunkKey: ChunkEntities] = [:]
    private var pending: [SceneChunk] = []
    private var stations: [String: Entity] = [:]
    private var trains: [String: [ModelEntity]] = [:]
    private var materialCache: [String: RealityKit.Material] = [:]
    private var carMesh: MeshResource?
    private var lastDepthPoint: GeoPoint?

    /// Rótulos de estaciones y bocas que hay ahora en la escena.
    private(set) var stationLabels: [LabelItem] = []
    /// Rótulo de la línea de profundidad, si se está dibujando.
    private(set) var depthLabel: LabelItem?

    init() {
        root.name = "metro"
        tracksNode.name = "vias"
        stationsNode.name = "estaciones"
        trainsNode.name = "trenes"
        depthNode.name = "profundidad"
        root.addChild(tracksNode)
        root.addChild(stationsNode)
        root.addChild(trainsNode)
        root.addChild(depthNode)
        root.addChild(grid.node)
    }

    var entityCount: Int {
        var count = stations.count + grid.entityCount + depthNode.children.count
        for chunk in chunks.values {
            count += (chunk.rails == nil ? 0 : 1) + (chunk.bed == nil ? 0 : 1) + (chunk.structure == nil ? 0 : 1)
        }
        for cars in trains.values {
            count += cars.count
        }
        return count
    }

    var pendingChunks: Int {
        pending.count
    }

    var trainCount: Int {
        trains.count
    }

    // MARK: - Origen

    /// Vacía la escena y fija un origen nuevo.
    func reset(frame: SceneFrame?) {
        self.frame = frame
        for chunk in chunks.values {
            chunk.parent.removeFromParent()
        }
        chunks.removeAll()
        pending.removeAll()
        for entity in stations.values {
            entity.removeFromParent()
        }
        stations.removeAll()
        stationLabels.removeAll()
        clearTrains()
        clearDepthLine()
        grid.reset()
    }

    // MARK: - Vías y túnel

    /// Recalcula qué hay a menos de 400 m de `userGeo`: quita lo que queda
    /// lejos, encola lo nuevo y reajusta el desvanecido de lo que sigue.
    func refresh(model: MetroModel, userGeo: GeoPoint) {
        guard frame != nil else {
            return
        }
        let wanted = model.chunks(near: userGeo, radius: SceneBuilder.radius)
        var wantedKeys = Set<ChunkKey>()
        var toBuild: [SceneChunk] = []

        for chunk in wanted {
            wantedKeys.insert(chunk.key)
            let band = SceneFade.band(distance: chunk.distance, bands: SceneBuilder.fadeBands)
            if var existing = chunks[chunk.key] {
                if existing.band != band {
                    existing.band = band
                    applyMaterials(&existing)
                    chunks[chunk.key] = existing
                }
            } else {
                toBuild.append(chunk)
            }
        }

        for (key, chunk) in chunks where !wantedKeys.contains(key) {
            chunk.parent.removeFromParent()
            chunks.removeValue(forKey: key)
        }

        // Lo más cercano se construye primero.
        pending = toBuild.sorted { $0.distance < $1.distance }
        refreshStations(model: model, userGeo: userGeo)
    }

    /// Construye unos pocos tramos pendientes. Se llama en cada imagen.
    func buildPending(model: MetroModel) {
        guard let frame = frame, !pending.isEmpty else {
            return
        }
        let count = min(SceneBuilder.chunksPerFrame, pending.count)
        let batch = pending.prefix(count)
        pending.removeFirst(count)

        for chunk in batch where chunks[chunk.key] == nil {
            let via = model.red.vias[chunk.key.via]
            let path = chunk.puntos.map { frame.rail($0) }
            let mesh = TunnelMesher.track(
                path: path,
                startChainage: chunk.startChainage,
                tunnel: via.tunel,
                tracks: via.pistas
            )
            let name = "\(via.id)-\(chunk.key.chunk)"
            let parent = Entity()
            parent.name = name
            var entities = ChunkEntities(
                parent: parent,
                rails: nil,
                bed: nil,
                structure: nil,
                band: SceneFade.band(distance: chunk.distance, bands: SceneBuilder.fadeBands),
                colorHex: model.colorHex(of: via)
            )
            // El material definitivo lo pone applyMaterials.
            let placeholder = Materials.unlit(.white)
            entities.rails = MeshFactory.entity(mesh.rails, material: placeholder, name: name + "-carriles")
            entities.bed = MeshFactory.entity(mesh.bed, material: placeholder, name: name + "-balasto")
            entities.structure = MeshFactory.entity(mesh.structure, material: placeholder, name: name + "-tunel")
            applyMaterials(&entities)
            for child in [entities.bed, entities.structure, entities.rails] {
                if let child = child {
                    parent.addChild(child)
                }
            }
            tracksNode.addChild(parent)
            chunks[chunk.key] = entities
        }
    }

    private func applyMaterials(_ chunk: inout ChunkEntities) {
        let band = chunk.band
        chunk.rails?.model?.materials = [material(hex: chunk.colorHex, part: "carriles", band: band)]
        chunk.bed?.model?.materials = [material(hex: chunk.colorHex, part: "balasto", band: band)]
        chunk.structure?.model?.materials = [material(hex: chunk.colorHex, part: "tunel", band: band)]
    }

    /// Material de una parte del túnel para un color de línea y una banda de
    /// desvanecido. Se guardan para compartirlos entre tramos.
    private func material(hex: String, part: String, band: Int) -> RealityKit.Material {
        let key = "\(hex)|\(part)|\(band)"
        if let cached = materialCache[key] {
            return cached
        }
        let fade = CGFloat(SceneFade.alpha(band: band, bands: SceneBuilder.fadeBands))
        let line = Materials.lineColor(hex: hex)
        let material: RealityKit.Material
        switch part {
        case "carriles":
            // Casi blancos, con un punto del color de la línea: es lo que más brilla.
            material = Materials.unlit(Materials.lighten(line, amount: 0.65), alpha: fade)
        case "balasto":
            material = Materials.unlit(line, alpha: 0.28 * fade)
        default:
            material = Materials.unlit(line, alpha: 0.85 * fade)
        }
        materialCache[key] = material
        return material
    }

    // MARK: - Estaciones y bocas

    private func refreshStations(model: MetroModel, userGeo: GeoPoint) {
        guard let frame = frame else {
            return
        }
        let nearby = model.stations(near: userGeo, radius: SceneBuilder.radius + 50)
        let wanted = Set(nearby.map { $0.estacion.id })

        for (id, entity) in stations where !wanted.contains(id) {
            entity.removeFromParent()
            stations.removeValue(forKey: id)
        }

        var labels: [LabelItem] = []
        for (estacion, _) in nearby {
            let rail = frame.position(lon: estacion.lon, lat: estacion.lat, cota: estacion.cotaCarril)
            if stations[estacion.id] == nil {
                let entity = makeStation(estacion, model: model, frame: frame, rail: rail)
                stationsNode.addChild(entity)
                stations[estacion.id] = entity
            }

            let depth = estacion.profundidad
            let detail: String
            if estacion.subterranea {
                detail = String(format: "%.0f m bajo el suelo", depth) + (estacion.origenCota == .estimado ? " (estimado)" : "")
            } else {
                detail = "en superficie"
            }
            labels.append(
                LabelItem(
                    id: "estacion-" + estacion.id,
                    kind: .station,
                    title: estacion.nombre,
                    detail: detail,
                    estimated: estacion.subterranea && estacion.origenCota == .estimado,
                    local: rail + SIMD3<Float>(0, estacion.subterranea ? 9 : 6, 0)
                )
            )

            for (index, boca) in estacion.bocas.enumerated() where Geo.distance(from: userGeo, to: boca.geo) < 120 {
                let ground = frame.position(lon: boca.lon, lat: boca.lat, cota: boca.cotaSuelo)
                labels.append(
                    LabelItem(
                        id: "boca-\(estacion.id)-\(index)",
                        kind: .boca,
                        title: boca.nombre.isEmpty ? "Boca" : boca.nombre,
                        detail: "Boca de " + estacion.nombre,
                        estimated: false,
                        local: ground + SIMD3<Float>(0, 2.4, 0)
                    )
                )
            }
        }
        stationLabels = labels
    }

    /// Caverna de la estación (caja de alambre con el suelo teñido) y un aro
    /// en el suelo por cada boca.
    private func makeStation(_ estacion: Estacion, model: MetroModel, frame: SceneFrame, rail: SIMD3<Float>) -> Entity {
        let parent = Entity()
        parent.name = "estacion-" + estacion.id

        // La caverna se orienta como la vía que pasa por ella.
        var direction = SIMD3<Float>(1, 0, 0)
        var colorHex = model.colorHex(ofLine: estacion.lineas.first)
        if let track = model.nearestTrack(to: estacion.geo, maxDistance: 80) {
            let via = model.red.vias[track.viaIndex]
            let a = via.puntos[track.segment]
            let b = via.puntos[min(track.segment + 1, via.puntos.count - 1)]
            direction = SceneFrame.direction(bearing: Geo.bearing(from: a.geo, to: b.geo))
            if estacion.lineas.isEmpty {
                colorHex = model.colorHex(of: via)
            }
        }
        let line = Materials.lineColor(hex: colorHex)

        if estacion.subterranea {
            var wire = MeshData()
            wire.addWireBox(
                center: rail + SIMD3<Float>(0, -0.4, 0),
                direction: direction,
                length: 95,
                width: 17,
                height: 7.5,
                thickness: 0.3
            )
            if let entity = MeshFactory.entity(
                wire, material: Materials.unlit(Materials.station, alpha: 0.9), name: "caverna"
            ) {
                parent.addChild(entity)
            }

            var floor = MeshData()
            floor.addBox(
                center: rail + SIMD3<Float>(0, -0.45, 0),
                direction: direction,
                length: 95,
                width: 17,
                height: 0.05
            )
            if let entity = MeshFactory.entity(floor, material: Materials.unlit(line, alpha: 0.22), name: "anden") {
                parent.addChild(entity)
            }
        } else {
            // En superficie basta un marco bajo a la altura del andén.
            var wire = MeshData()
            wire.addWireBox(
                center: rail,
                direction: direction,
                length: 95,
                width: 12,
                height: 1.1,
                thickness: 0.25
            )
            if let entity = MeshFactory.entity(
                wire, material: Materials.unlit(Materials.station, alpha: 0.7), name: "anden"
            ) {
                parent.addChild(entity)
            }
        }

        var rings = MeshData()
        for boca in estacion.bocas {
            let ground = frame.position(lon: boca.lon, lat: boca.lat, cota: boca.cotaSuelo)
            rings.addAnnulus(center: ground + SIMD3<Float>(0, 0.05, 0), inner: 0.9, outer: 1.25, segments: 28)
            // Un poste fino para ver la boca de lejos.
            rings.addBar(from: ground, to: ground + SIMD3<Float>(0, 2.2, 0), thickness: 0.08)
        }
        if let entity = MeshFactory.entity(rings, material: Materials.unlit(Materials.boca, alpha: 0.9), name: "bocas") {
            parent.addChild(entity)
        }
        return parent
    }

    // MARK: - Trenes

    /// Coloca los trenes cercanos. Las entidades se reutilizan por id de tren.
    func updateTrains(_ positions: [TrainPosition], model: MetroModel, userGeo: GeoPoint) {
        guard let frame = frame else {
            return
        }
        var seen = Set<String>()
        let spacing = Double(SceneBuilder.carLength + SceneBuilder.carGap)

        for train in positions where train.rutaIndex < model.rutas.count {
            let route = model.rutas[train.rutaIndex]
            let head = route.point(at: train.chainage)
            guard Geo.distance(from: userGeo, to: head.geo) < SceneBuilder.radius + 150 else {
                continue
            }
            seen.insert(train.id)

            var cars = trains[train.id] ?? []
            if cars.isEmpty {
                cars = makeCars(colorHex: model.colorHex(ofLine: train.linea ?? route.ruta.linea))
                for car in cars {
                    trainsNode.addChild(car)
                }
                trains[train.id] = cars
            }
            for (index, car) in cars.enumerated() {
                // La cabeza va en `chainage`; los coches cuelgan hacia atrás.
                let chainage = train.chainage - (Double(index) + 0.5) * spacing
                let point = route.point(at: chainage)
                let bearing = route.bearing(at: chainage)
                car.position = frame.rail(point) + SIMD3<Float>(0, 1.95, 0)
                // El eje largo del coche es z; girar −rumbo alrededor de +y lo
                // lleva del norte (−z) a la dirección de avance.
                car.orientation = simd_quatf(angle: Float(-bearing * .pi / 180), axis: SIMD3<Float>(0, 1, 0))
            }
        }

        for (id, cars) in trains where !seen.contains(id) {
            for car in cars {
                car.removeFromParent()
            }
            trains.removeValue(forKey: id)
        }
    }

    func clearTrains() {
        for cars in trains.values {
            for car in cars {
                car.removeFromParent()
            }
        }
        trains.removeAll()
    }

    private func makeCars(colorHex: String) -> [ModelEntity] {
        if carMesh == nil {
            carMesh = MeshResource.generateBox(width: 2.6, height: 3.5, depth: SceneBuilder.carLength)
        }
        guard let mesh = carMesh else {
            return []
        }
        let color = Materials.lighten(Materials.lineColor(hex: colorHex), amount: 0.25)
        let material = Materials.unlit(color, alpha: 0.95)
        return (0..<SceneBuilder.carsPerTrain).map { index in
            let car = ModelEntity(mesh: mesh, materials: [material])
            car.name = "coche-\(index)"
            return car
        }
    }

    // MARK: - Línea de profundidad

    /// Línea vertical desde el suelo hasta el carril en el punto de vía más
    /// cercano, con los metros. Solo se dibuja si la vía va por debajo.
    func updateDepthLine(track: NearestTrack?, userGround: Double?) {
        guard let frame = frame, let track = track, track.distance < 80 else {
            clearDepthLine()
            return
        }
        let point = track.point
        // Sobre la vía, el suelo es el del punto de vía; el del usuario sirve
        // para dar la profundidad «bajo tus pies» cuando está encima.
        let groundCota = track.distance < 15 ? (userGround ?? point.cotaSuelo) : point.cotaSuelo
        let depth = groundCota - point.cotaCarril
        guard depth > 2 else {
            clearDepthLine()
            return
        }

        let top = frame.position(lon: point.lon, lat: point.lat, cota: groundCota)
        let bottom = frame.rail(point)
        depthLabel = LabelItem(
            id: "profundidad",
            kind: .depth,
            title: String(format: "%.0f m", depth),
            detail: track.distance < 15 ? "bajo tus pies" : "hasta la vía",
            estimated: false,
            local: (top + bottom) / 2
        )

        if let last = lastDepthPoint, Geo.distance(from: last, to: point.geo) < 1.5, !depthNode.children.isEmpty {
            return
        }
        lastDepthPoint = point.geo
        for child in Array(depthNode.children) {
            child.removeFromParent()
        }
        var mesh = MeshData()
        mesh.addBar(from: top, to: bottom, thickness: 0.14)
        mesh.addAnnulus(center: top + SIMD3<Float>(0, 0.03, 0), inner: 0.35, outer: 0.6, segments: 24)
        mesh.addAnnulus(center: bottom + SIMD3<Float>(0, 0.06, 0), inner: 0.5, outer: 0.9, segments: 24)
        if let entity = MeshFactory.entity(mesh, material: Materials.unlit(Materials.depthLine, alpha: 0.95), name: "linea") {
            depthNode.addChild(entity)
        }
    }

    private func clearDepthLine() {
        for child in Array(depthNode.children) {
            child.removeFromParent()
        }
        lastDepthPoint = nil
        depthLabel = nil
    }
}
