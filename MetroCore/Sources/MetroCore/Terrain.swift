import Foundation

public enum TerrainError: Error, Equatable {
    case sizeMismatch(expectedBytes: Int, actualBytes: Int)
    case invalidGrid
}

/// Cota del suelo a partir de la rejilla de `relieve.bin`.
///
/// Formato: enteros de 16 bits little-endian, en decímetros, por filas;
/// la fila 0 es la más al sur y la columna 0 la más al oeste.
public struct Terrain: Sendable {
    public let info: RelieveInfo
    private let values: [Int16]
    private let noData: Int16

    public init(info: RelieveInfo, values: [Int16]) throws {
        guard info.filas > 0, info.columnas > 0, info.origen.count == 2,
              info.pasoLon > 0, info.pasoLat > 0
        else {
            throw TerrainError.invalidGrid
        }
        guard values.count == info.filas * info.columnas else {
            throw TerrainError.sizeMismatch(
                expectedBytes: info.filas * info.columnas * 2,
                actualBytes: values.count * 2
            )
        }
        self.info = info
        self.values = values
        self.noData = Int16(clamping: info.sinDato)
    }

    public init(info: RelieveInfo, data: Data) throws {
        let expected = info.filas * info.columnas * 2
        guard info.filas > 0, info.columnas > 0 else {
            throw TerrainError.invalidGrid
        }
        guard data.count == expected else {
            throw TerrainError.sizeMismatch(expectedBytes: expected, actualBytes: data.count)
        }
        var values = [Int16](repeating: 0, count: expected / 2)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            for index in 0..<values.count {
                let low = UInt16(bytes[index * 2])
                let high = UInt16(bytes[index * 2 + 1])
                values[index] = Int16(bitPattern: low | (high << 8))
            }
        }
        try self.init(info: info, values: values)
    }

    /// Cota del suelo en metros sobre el nivel del mar, con interpolación
    /// bilineal. `nil` fuera de la rejilla o donde no hay dato.
    public func elevation(at point: GeoPoint) -> Double? {
        var column = (point.longitude - info.origen[0]) / info.pasoLon
        var row = (point.latitude - info.origen[1]) / info.pasoLat
        // Tolerancia para los puntos que caen justo en el borde de la rejilla.
        let epsilon = 1e-6
        let maxColumn = Double(info.columnas - 1)
        let maxRow = Double(info.filas - 1)
        guard column >= -epsilon, row >= -epsilon,
              column <= maxColumn + epsilon, row <= maxRow + epsilon
        else {
            return nil
        }
        column = min(max(column, 0), maxColumn)
        row = min(max(row, 0), maxRow)

        let column0 = min(Int(column), info.columnas - 1)
        let row0 = min(Int(row), info.filas - 1)
        let column1 = min(column0 + 1, info.columnas - 1)
        let row1 = min(row0 + 1, info.filas - 1)
        let fx = column - Double(column0)
        let fy = row - Double(row0)

        // Media ponderada de las esquinas que tienen dato.
        let corners: [(Int, Int, Double)] = [
            (row0, column0, (1 - fx) * (1 - fy)),
            (row0, column1, fx * (1 - fy)),
            (row1, column0, (1 - fx) * fy),
            (row1, column1, fx * fy)
        ]
        var sum = 0.0
        var weight = 0.0
        var fallback: Double?
        for (r, c, w) in corners {
            let raw = values[r * info.columnas + c]
            if raw == noData {
                continue
            }
            let meters = Double(raw) / 10
            fallback = fallback ?? meters
            sum += meters * w
            weight += w
        }
        if weight > 1e-9 {
            return sum / weight
        }
        return fallback
    }
}
