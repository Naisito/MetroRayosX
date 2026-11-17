import XCTest
@testable import MetroCore

final class MetroModelTests: XCTestCase {
    private let model = TestNetwork.model()

    // MARK: - Índice espacial

    func testElIndiceEncuentraLasViasCercanas() {
        let index = SpatialIndex(vias: model.red.vias)
        // Sobre el túnel, lejos de la vía de superficie.
        XCTAssertEqual(index.candidates(near: TestNetwork.geo(east: 300, north: 20), radius: 50), [0])
        // En la esquina están las dos.
        XCTAssertEqual(index.candidates(near: TestNetwork.geo(east: 1000, north: 10), radius: 50), [0, 1])
        // Lejos de todo.
        XCTAssertEqual(index.candidates(near: TestNetwork.geo(east: 300, north: 3000), radius: 400), [])
    }

    func testElIndiceNoPierdeViasConRadiosGrandes() {
        let index = SpatialIndex(vias: model.red.vias)
        XCTAssertEqual(index.candidates(near: TestNetwork.geo(east: 700, north: 300), radius: 400), [0, 1])
    }

    // MARK: - Vía más cercana

    func testViaMasCercanaYProfundidad() throws {
        let track = try XCTUnwrap(model.nearestTrack(to: TestNetwork.geo(east: 302, north: 30)))
        XCTAssertEqual(track.viaIndex, 0)
        XCTAssertEqual(track.distance, 30, accuracy: 0.05)
        XCTAssertEqual(track.chainage, 302, accuracy: 0.1)
        XCTAssertEqual(track.point.cotaCarril, 0, accuracy: 1e-9)
        XCTAssertEqual(track.point.profundidad, 20, accuracy: 1e-9)
    }

    func testLaCotaDelCarrilSeInterpolaEntrePuntos() throws {
        // En la rampa de superficie: 20 m de subida en 400 m.
        let track = try XCTUnwrap(model.nearestTrack(to: TestNetwork.geo(east: 1010, north: 102)))
        XCTAssertEqual(track.viaIndex, 1)
        XCTAssertEqual(track.point.cotaCarril, 5.1, accuracy: 0.02)
    }

    func testSinViasCercaNoHayResultado() {
        XCTAssertNil(model.nearestTrack(to: TestNetwork.geo(east: 0, north: 5000)))
        XCTAssertNil(model.nearestTrack(to: TestNetwork.geo(east: 300, north: 80), maxDistance: 50))
    }

    // MARK: - Tramos para la escena

    func testLosTramosSeEncadenanSinHuecos() {
        let chunks = model.chunks(near: TestNetwork.geo(east: 500, north: 0), radius: 2000)
            .filter { $0.key.via == 0 }
            .sorted { $0.key.chunk < $1.key.chunk }
        XCTAssertEqual(chunks.count, 10, "1000 m en tramos de 20 puntos (100 m)")
        for i in 1..<chunks.count {
            XCTAssertEqual(chunks[i].puntos.first, chunks[i - 1].puntos.last)
            XCTAssertEqual(chunks[i].startChainage, Double(i) * 100, accuracy: 0.01)
        }
        XCTAssertEqual(chunks.map { $0.puntos.count }, [Int](repeating: 21, count: 10))
    }

    func testSoloSeDevuelvenLosTramosDentroDelRadio() {
        let chunks = model.chunks(near: TestNetwork.geo(east: 0, north: 0), radius: 250)
        XCTAssertEqual(Set(chunks.map { $0.key.via }), [0])
        XCTAssertEqual(chunks.map { $0.key.chunk }.sorted(), [0, 1, 2])
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.distance, 250)
        }
    }

    // MARK: - Estaciones

    func testEstacionMasCercanaYBocas() throws {
        let here = TestNetwork.geo(east: 590, north: 10)
        let nearest = try XCTUnwrap(model.nearestStation(to: here))
        XCTAssertEqual(nearest.estacion.nombre, "Centro")
        XCTAssertEqual(nearest.distance, 14.1, accuracy: 0.1)

        let bocas = model.nearestBocas(to: here, count: 3, maxDistance: 2000)
        XCTAssertEqual(bocas.map { $0.estacion.nombre }, ["Centro", "Oeste", "Norte"])
        XCTAssertEqual(bocas[0].distance, 28.3, accuracy: 0.1)
        XCTAssertEqual(model.nearestBocas(to: here, count: 3, maxDistance: 100).count, 1)
    }

    func testBuscarEstacionPorParada() {
        XCTAssertEqual(model.station(forStop: "2")?.nombre, "Centro")
        XCTAssertEqual(model.station(forStop: "2.0")?.nombre, "Centro")
        XCTAssertNil(model.station(forStop: "99"))
    }

    func testResumenDeUnaPosicion() {
        let summary = model.summary(at: TestNetwork.geo(east: 595, north: 5))
        XCTAssertEqual(summary.estacion?.nombre, "Centro")
        XCTAssertEqual(summary.via?.viaIndex, 0)
        // Sin rejilla de relieve, el suelo es el del punto de vía más cercano.
        XCTAssertEqual(summary.cotaSuelo ?? .nan, 20, accuracy: 1e-9)
        XCTAssertEqual(summary.profundidad ?? .nan, 20, accuracy: 1e-9)
        XCTAssertTrue(summary.profundidadEstimada)
    }

    func testColorDeUnaVia() {
        XCTAssertEqual(model.colorHex(of: model.red.vias[0]), "#FF6505")
        XCTAssertEqual(model.colorHex(ofLine: "L9"), "#ff7a00")
    }

    // MARK: - Rutas

    func testLasRutasRecorrenLasViasEnOrden() throws {
        XCTAssertEqual(model.rutas.count, 2)
        let forward = model.rutas[0]
        XCTAssertEqual(forward.length, 1500, accuracy: 0.5)
        XCTAssertEqual(forward.stops.map { $0.estacionID }, ["1", "2", "3"])
        XCTAssertEqual(try XCTUnwrap(forward.chainage(ofStation: "2")), 600, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(forward.chainage(ofStation: "3")), 1450, accuracy: 0.5)

        let backward = model.rutas[1]
        XCTAssertEqual(backward.length, 1500, accuracy: 0.5)
        XCTAssertEqual(backward.stops.map { $0.estacionID }, ["3", "2", "1"])
        XCTAssertEqual(try XCTUnwrap(backward.chainage(ofStation: "1")), 1400, accuracy: 0.5)
    }

    func testPuntoYRumboSobreUnaRuta() {
        let route = model.rutas[0]
        let inTunnel = route.point(at: 300)
        XCTAssertEqual(Geo.distance(from: inTunnel.geo, to: TestNetwork.geo(east: 300, north: 0)), 0, accuracy: 0.05)
        XCTAssertEqual(route.bearing(at: 300), 90, accuracy: 0.1)

        let onSurface = route.point(at: 1200)
        XCTAssertEqual(Geo.distance(from: onSurface.geo, to: TestNetwork.geo(east: 1000, north: 200)), 0, accuracy: 0.05)
        XCTAssertEqual(onSurface.cotaCarril, 10, accuracy: 0.05)
        XCTAssertEqual(route.bearing(at: 1200), 0, accuracy: 0.1)

        XCTAssertEqual(model.rutas[1].bearing(at: 100), 180, accuracy: 0.1)
    }

    func testAnteriorParadaDeUnaRuta() {
        let route = model.rutas[0]
        XCTAssertEqual(route.stop(before: 600)?.estacionID, "1")
        XCTAssertEqual(route.stop(before: 700)?.estacionID, "2")
        XCTAssertNil(route.stop(before: 100))
    }

    // MARK: - Datos reales

    func testBajoMoyuaHayMetroAUnosVeinteMetros() throws {
        let real = try Fixtures.realModel()
        let eliptikoa = try XCTUnwrap(real.red.estaciones.first { $0.nombre == "Eliptikoa" })
        let summary = real.summary(at: eliptikoa.geo)
        XCTAssertEqual(summary.estacion?.id, eliptikoa.id)
        XCTAssertLessThan(try XCTUnwrap(summary.via).distance, 30)
        let depth = try XCTUnwrap(summary.profundidad)
        XCTAssertGreaterThan(depth, 10)
        XCTAssertLessThan(depth, 35)
    }

    func testEnLaRedRealSeDibujanTramosAlrededorDeUnaEstacion() throws {
        let real = try Fixtures.realModel()
        let abando = try XCTUnwrap(real.red.estaciones.first { $0.nombre.contains("Abando") })
        let chunks = real.chunks(near: abando.geo, radius: 400)
        XCTAssertGreaterThan(chunks.count, 8)
        XCTAssertLessThan(chunks.count, 200)
        for chunk in chunks {
            XCTAssertGreaterThanOrEqual(chunk.puntos.count, 2)
            XCTAssertLessThanOrEqual(chunk.distance, 400)
        }
    }
}
