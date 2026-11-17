import XCTest
@testable import MetroCore

final class ModelTests: XCTestCase {
    private let sample = """
    {
      "version": 1,
      "generado": "2026-11-17",
      "atribucion": ["© OpenStreetMap contributors (ODbL)"],
      "lineas": [{"id": "L1", "nombre": "Etxebarri - Plentzia", "color": "#FF6505"}],
      "vias": [{
        "id": "w1", "lineas": ["L1", "L2"], "tunel": true, "pistas": 2,
        "puntos": [[-2.935, 43.263, -2.5, 18.5], [-2.9349, 43.2631, -2.6, 18.7]]
      }, {
        "id": "w2", "puntos": [[-2.9349, 43.2631, 5, 5], [-2.9348, 43.2632, 5, 5]]
      }],
      "rutas": [{"id": "L1-0", "linea": "L1", "nombre": "A → B",
                 "tramos": [{"via": "w1", "inv": false}, {"via": "w2", "inv": true}]}],
      "estaciones": [{
        "id": "8", "nombre": "Eliptikoa", "lat": 43.2626748, "lon": -2.9334619,
        "cotaCarril": -2.3, "cotaSuelo": 18.6, "subterranea": true, "origenCota": "estimado",
        "lineas": ["L1", "L2"], "paradas": ["8", "8.0"],
        "bocas": [{"nombre": "Ascensor", "lat": 43.2626609, "lon": -2.933751, "cotaSuelo": 18.4}]
      }, {
        "id": "x", "nombre": "Sin extras", "lat": 43.0, "lon": -2.0,
        "cotaCarril": 1, "cotaSuelo": 2, "origenCota": "inventado"
      }],
      "relieve": {"paso_m": 10, "origen": [-3.0475967, 43.2313129], "paso_lon": 0.000123471,
                  "paso_lat": 8.9832e-05, "filas": 1944, "columnas": 1395, "sin_dato": -32768,
                  "fichero": "relieve.bin"}
    }
    """

    func testDecodificaElFormatoDeMetroJSON() throws {
        let red = try NetworkLoader.decode(Data(sample.utf8))
        XCTAssertEqual(red.version, 1)
        XCTAssertEqual(red.lineas, [Linea(id: "L1", nombre: "Etxebarri - Plentzia", color: "#FF6505")])
        XCTAssertEqual(red.vias.count, 2)

        let via = red.vias[0]
        XCTAssertEqual(via.id, "w1")
        XCTAssertEqual(via.lineas, ["L1", "L2"])
        XCTAssertTrue(via.tunel)
        XCTAssertEqual(via.pistas, 2)
        XCTAssertEqual(via.puntos[0], PuntoVia(lon: -2.935, lat: 43.263, cotaCarril: -2.5, cotaSuelo: 18.5))
        XCTAssertEqual(via.puntos[0].profundidad, 21, accuracy: 1e-9)

        XCTAssertEqual(red.rutas[0].tramos, [TramoRuta(via: "w1", inv: false), TramoRuta(via: "w2", inv: true)])

        let estacion = red.estaciones[0]
        XCTAssertEqual(estacion.nombre, "Eliptikoa")
        XCTAssertEqual(estacion.paradas, ["8", "8.0"])
        XCTAssertEqual(estacion.origenCota, .estimado)
        XCTAssertEqual(estacion.bocas.first?.nombre, "Ascensor")
        XCTAssertEqual(estacion.profundidad, 20.9, accuracy: 1e-9)

        XCTAssertEqual(red.relieve?.filas, 1944)
        XCTAssertEqual(red.relieve?.pasoLat, 8.9832e-05)
        XCTAssertEqual(red.relieve?.sinDato, -32768)
    }

    func testLosCamposOpcionalesTienenValorPorDefecto() throws {
        let red = try NetworkLoader.decode(Data(sample.utf8))
        let via = red.vias[1]
        XCTAssertEqual(via.lineas, [])
        XCTAssertFalse(via.tunel)
        XCTAssertEqual(via.pistas, 1)

        let estacion = red.estaciones[1]
        XCTAssertTrue(estacion.subterranea)
        XCTAssertEqual(estacion.origenCota, .estimado, "Un origen desconocido cuenta como estimado")
        XCTAssertEqual(estacion.lineas, [])
        XCTAssertEqual(estacion.paradas, [])
        XCTAssertEqual(estacion.bocas, [])
    }

    func testCodificarYDecodificarDevuelveLoMismo() throws {
        let red = TestNetwork.make()
        let data = try JSONEncoder().encode(red)
        let again = try NetworkLoader.decode(data)
        XCTAssertEqual(again, red)
    }

    func testInterpolacionDePuntosDeVia() {
        let a = PuntoVia(lon: 0, lat: 0, cotaCarril: 0, cotaSuelo: 10)
        let b = PuntoVia(lon: 2, lat: 4, cotaCarril: -8, cotaSuelo: 20)
        let middle = a.interpolated(to: b, t: 0.25)
        XCTAssertEqual(middle, PuntoVia(lon: 0.5, lat: 1, cotaCarril: -2, cotaSuelo: 12.5))
    }

    // MARK: - Datos reales

    func testLaRedRealSeCargaEntera() throws {
        let model = try Fixtures.realModel()
        let red = model.red
        XCTAssertGreaterThan(red.vias.count, 100)
        XCTAssertGreaterThanOrEqual(red.estaciones.count, 42)
        XCTAssertEqual(Set(red.lineas.map { $0.id }), ["L1", "L2", "L3"])
        XCTAssertNotNil(model.terrain, "relieve.bin debe cargarse con la red")
        for via in red.vias {
            XCTAssertGreaterThanOrEqual(via.puntos.count, 2, via.id)
        }
        for linea in red.lineas {
            XCTAssertNotNil(ColorHex.rgb(linea.color), "Color no válido en \(linea.id): \(linea.color)")
        }
    }

    func testLasRutasRealesSonContinuasYTienenSusEstaciones() throws {
        let model = try Fixtures.realModel()
        XCTAssertEqual(model.rutas.count, model.red.rutas.count)
        for route in model.rutas {
            var maxGap = 0.0
            for i in 1..<route.puntos.count {
                maxGap = max(maxGap, route.cumulative[i] - route.cumulative[i - 1])
            }
            XCTAssertLessThan(maxGap, 6, "Hueco en la ruta \(route.ruta.id)")

            let expected = model.red.estaciones.filter { $0.lineas.contains(route.ruta.linea) }.count
            XCTAssertEqual(route.stops.count, expected, "Estaciones de la ruta \(route.ruta.id)")
        }
    }

    func testEnTunelElCarrilRealVaBajoElSuelo() throws {
        let model = try Fixtures.realModel()
        var deepest = 0.0
        for via in model.red.vias where via.tunel {
            for punto in via.puntos {
                deepest = max(deepest, punto.profundidad)
            }
        }
        // La L3 pasa bajo el monte Artxanda, a más de 100 m de la superficie.
        XCTAssertGreaterThan(deepest, 20)
        XCTAssertLessThan(deepest, 300)
    }
}
