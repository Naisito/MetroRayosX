import XCTest
@testable import MetroCore

final class TerrainTests: XCTestCase {
    /// Rejilla de 3 filas × 3 columnas, paso de 0,001°, origen en (−3, 43).
    /// Valores en decímetros; fila 0 = sur.
    private func makeTerrain(_ values: [Int16]) throws -> Terrain {
        let info = RelieveInfo(
            pasoM: 100, origen: [-3.0, 43.0], pasoLon: 0.001, pasoLat: 0.001, filas: 3, columnas: 3
        )
        return try Terrain(info: info, values: values)
    }

    private let noData: Int16 = -32768

    func testValorExactoEnLosNodos() throws {
        let terrain = try makeTerrain([
            100, 200, 300,
            400, 500, 600,
            700, 800, 900
        ])
        XCTAssertEqual(try XCTUnwrap(terrain.elevation(at: GeoPoint(latitude: 43.0, longitude: -3.0))), 10, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(terrain.elevation(at: GeoPoint(latitude: 43.0, longitude: -2.998))), 30, accuracy: 1e-6)
        // Una fila más al norte = segunda fila del fichero.
        XCTAssertEqual(try XCTUnwrap(terrain.elevation(at: GeoPoint(latitude: 43.001, longitude: -3.0))), 40, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(terrain.elevation(at: GeoPoint(latitude: 43.002, longitude: -2.998))), 90, accuracy: 1e-6)
    }

    func testInterpolacionBilineal() throws {
        let terrain = try makeTerrain([
            100, 200, 300,
            400, 500, 600,
            700, 800, 900
        ])
        // Centro de la celda inferior izquierda: media de 10, 20, 40 y 50.
        let center = try XCTUnwrap(terrain.elevation(at: GeoPoint(latitude: 43.0005, longitude: -2.9995)))
        XCTAssertEqual(center, 30, accuracy: 1e-6)
        // A un cuarto del camino entre dos nodos de la fila sur.
        let quarter = try XCTUnwrap(terrain.elevation(at: GeoPoint(latitude: 43.0, longitude: -2.99975)))
        XCTAssertEqual(quarter, 12.5, accuracy: 1e-6)
    }

    func testFueraDeLaRejillaNoHayDato() throws {
        let terrain = try makeTerrain([Int16](repeating: 100, count: 9))
        XCTAssertNil(terrain.elevation(at: GeoPoint(latitude: 42.999, longitude: -3.0)))
        XCTAssertNil(terrain.elevation(at: GeoPoint(latitude: 43.0, longitude: -3.0001)))
        XCTAssertNil(terrain.elevation(at: GeoPoint(latitude: 43.0021, longitude: -3.0)))
        XCTAssertNil(terrain.elevation(at: GeoPoint(latitude: 43.0, longitude: -2.9979)))
    }

    func testLasCeldasSinDatoSeIgnoran() throws {
        let terrain = try makeTerrain([
            100, noData, noData,
            300, noData, noData,
            noData, noData, noData
        ])
        // Dos esquinas con dato y dos sin dato: media ponderada de las válidas.
        let partial = try XCTUnwrap(terrain.elevation(at: GeoPoint(latitude: 43.0005, longitude: -2.9995)))
        XCTAssertEqual(partial, 20, accuracy: 1e-6)
        // Ninguna esquina con dato.
        XCTAssertNil(terrain.elevation(at: GeoPoint(latitude: 43.0015, longitude: -2.9985)))
    }

    func testLeeEnterosLittleEndianEnDecimetros() throws {
        let info = RelieveInfo(
            pasoM: 100, origen: [-3.0, 43.0], pasoLon: 0.001, pasoLat: 0.001, filas: 1, columnas: 2
        )
        // 0x0102 = 258 dm = 25,8 m; 0xFFF6 = −10 dm = −1,0 m.
        let data = Data([0x02, 0x01, 0xF6, 0xFF])
        let terrain = try Terrain(info: info, data: data)
        XCTAssertEqual(try XCTUnwrap(terrain.elevation(at: GeoPoint(latitude: 43.0, longitude: -3.0))), 25.8, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(terrain.elevation(at: GeoPoint(latitude: 43.0, longitude: -2.999))), -1.0, accuracy: 1e-6)
    }

    func testElTamanoDelFicheroDebeCoincidir() {
        let info = RelieveInfo(
            pasoM: 100, origen: [-3.0, 43.0], pasoLon: 0.001, pasoLat: 0.001, filas: 2, columnas: 2
        )
        XCTAssertThrowsError(try Terrain(info: info, data: Data([0, 0, 0, 0]))) { error in
            XCTAssertEqual(error as? TerrainError, .sizeMismatch(expectedBytes: 8, actualBytes: 4))
        }
        XCTAssertThrowsError(try Terrain(info: info, values: [1, 2, 3]))
    }

    // MARK: - Datos reales

    func testElRelieveRealCoincideConLasCotasDeLasEstaciones() throws {
        let model = try Fixtures.realModel()
        let terrain = try XCTUnwrap(model.terrain)
        var checked = 0
        for estacion in model.red.estaciones {
            for boca in estacion.bocas {
                let elevation = try XCTUnwrap(
                    terrain.elevation(at: boca.geo),
                    "Sin relieve en una boca de \(estacion.nombre)"
                )
                XCTAssertEqual(elevation, boca.cotaSuelo, accuracy: 3, "Boca de \(estacion.nombre)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 100)
    }

    func testElRelieveRealEstaOrientadoSurNorte() throws {
        // Artxanda (norte del centro) está mucho más alto que la ría.
        let model = try Fixtures.realModel()
        let eliptikoa = try XCTUnwrap(model.red.estaciones.first { $0.nombre == "Eliptikoa" })
        let ground = try XCTUnwrap(model.groundElevation(at: eliptikoa.geo))
        XCTAssertEqual(ground, eliptikoa.cotaSuelo, accuracy: 3)
        XCTAssertGreaterThan(ground, 5)
        XCTAssertLessThan(ground, 40)
    }
}
