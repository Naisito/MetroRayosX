import Foundation

/// Rejilla para pedir «vías a menos de R metros» sin recorrer toda la red.
public struct SpatialIndex: Sendable {
    private struct Cell: Hashable, Sendable {
        let x: Int32
        let z: Int32
    }

    public let cellSize: Double
    private let frame: LocalFrame
    private let cells: [Cell: [Int32]]

    public init(vias: [Via], cellSize: Double = 100) {
        self.cellSize = cellSize
        let origin = vias.first?.puntos.first?.geo ?? GeoPoint(latitude: 43.263, longitude: -2.935)
        let frame = LocalFrame(origin: origin)
        self.frame = frame

        var cells: [Cell: [Int32]] = [:]
        for (viaIndex, via) in vias.enumerated() {
            var seen = Set<Cell>()
            for punto in via.puntos {
                let position = frame.plane(lon: punto.lon, lat: punto.lat)
                let cell = Cell(
                    x: Int32((position.x / cellSize).rounded(.down)),
                    z: Int32((position.z / cellSize).rounded(.down))
                )
                if seen.insert(cell).inserted {
                    cells[cell, default: []].append(Int32(viaIndex))
                }
            }
        }
        self.cells = cells
    }

    /// Índices de las vías que pueden tener algún punto a menos de `radius`
    /// metros. Es una preselección generosa: quien llama filtra con precisión.
    public func candidates(near point: GeoPoint, radius: Double) -> [Int] {
        let center = frame.plane(point)
        // Margen por la separación entre puntos (5 m) y la distorsión del plano.
        let reach = radius * 1.01 + 10
        let minX = Int32(((center.x - reach) / cellSize).rounded(.down))
        let maxX = Int32(((center.x + reach) / cellSize).rounded(.down))
        let minZ = Int32(((center.z - reach) / cellSize).rounded(.down))
        let maxZ = Int32(((center.z + reach) / cellSize).rounded(.down))
        guard minX <= maxX, minZ <= maxZ else {
            return []
        }

        var found = Set<Int32>()
        for x in minX...maxX {
            for z in minZ...maxZ {
                if let list = cells[Cell(x: x, z: z)] {
                    found.formUnion(list)
                }
            }
        }
        return found.map { Int($0) }.sorted()
    }
}
