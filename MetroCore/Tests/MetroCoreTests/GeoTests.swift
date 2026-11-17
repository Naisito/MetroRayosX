import XCTest
@testable import MetroCore

final class GeoTests: XCTestCase {
    private let bilbao = GeoPoint(latitude: 43.263, longitude: -2.935)

    func testUnaMilesimaDeGradoAlNorteSonUnos111Metros() {
        let point = GeoPoint(latitude: 43.264, longitude: -2.935)
        let offset = Geo.localOffset(of: point, from: bilbao)
        XCTAssertEqual(offset.north, 111.32, accuracy: 0.05)
        XCTAssertEqual(offset.east, 0, accuracy: 1e-6)
    }

    func testUnaMilesimaDeGradoAlEsteSonUnos81MetrosEnBilbao() {
        let point = GeoPoint(latitude: 43.263, longitude: -2.934)
        let offset = Geo.localOffset(of: point, from: bilbao)
        XCTAssertEqual(offset.east, 81.06, accuracy: 0.05)
        XCTAssertEqual(offset.north, 0, accuracy: 1e-6)
    }

    func testSurYOesteSonNegativos() {
        let point = GeoPoint(latitude: 43.262, longitude: -2.936)
        let offset = Geo.localOffset(of: point, from: bilbao)
        XCTAssertLessThan(offset.north, 0)
        XCTAssertLessThan(offset.east, 0)
    }

    func testElMismoPuntoNoSeDesplaza() {
        let offset = Geo.localOffset(of: bilbao, from: bilbao)
        XCTAssertEqual(offset, LocalOffset(east: 0, north: 0))
        XCTAssertEqual(offset.distance, 0)
    }

    func testLaDistanciaEsCasiSimetrica() {
        // La aproximación plana usa la latitud del punto de partida, así que
        // ida y vuelta difieren unos centímetros por kilómetro.
        let a = Landmarks.moyua.point
        let b = Landmarks.cascoViejo.point
        let ida = Geo.distance(from: a, to: b)
        let vuelta = Geo.distance(from: b, to: a)
        XCTAssertEqual(ida, vuelta, accuracy: 0.2)
    }

    func testMoyuaYCascoViejoEstanAPocoMasDeUnKilometro() {
        let distance = Geo.distance(from: Landmarks.moyua.point, to: Landmarks.cascoViejo.point)
        XCTAssertGreaterThan(distance, 900)
        XCTAssertLessThan(distance, 1300)
    }

    func testDistanciaDeUnTriangulo345() {
        let offset = LocalOffset(east: 3, north: -4)
        XCTAssertEqual(offset.distance, 5, accuracy: 1e-9)
    }

    func testRumbos() {
        let north = GeoPoint(latitude: 43.264, longitude: -2.935)
        let east = GeoPoint(latitude: 43.263, longitude: -2.934)
        let southwest = GeoPoint(latitude: 43.262, longitude: -2.9363734)
        XCTAssertEqual(Geo.bearing(from: bilbao, to: north), 0, accuracy: 0.01)
        XCTAssertEqual(Geo.bearing(from: bilbao, to: east), 90, accuracy: 0.01)
        XCTAssertEqual(Geo.bearing(from: bilbao, to: southwest), 225, accuracy: 0.5)
    }

    // MARK: - Ejes de la escena

    /// El error más probable del proyecto: el signo de z. Norte es −z.
    func testElNorteEsZNegativoYElEsteXPositivo() {
        let frame = LocalFrame(origin: bilbao)
        let north = frame.plane(GeoPoint(latitude: 43.264, longitude: -2.935))
        XCTAssertEqual(north.x, 0, accuracy: 1e-6)
        XCTAssertEqual(north.z, -111.32, accuracy: 0.05)

        let east = frame.plane(GeoPoint(latitude: 43.263, longitude: -2.934))
        XCTAssertEqual(east.x, 81.06, accuracy: 0.05)
        XCTAssertEqual(east.z, 0, accuracy: 1e-6)

        let south = frame.plane(GeoPoint(latitude: 43.262, longitude: -2.935))
        XCTAssertGreaterThan(south.z, 0)
    }

    func testIdaYVueltaEntreGeograficasYPlano() {
        let frame = LocalFrame(origin: bilbao)
        let point = GeoPoint(latitude: 43.2671, longitude: -2.9412)
        let back = frame.geo(frame.plane(point))
        XCTAssertEqual(back.latitude, point.latitude, accuracy: 1e-10)
        XCTAssertEqual(back.longitude, point.longitude, accuracy: 1e-10)

        let moved = frame.geo(Vec2(x: 100, z: -200))
        let offset = Geo.localOffset(of: moved, from: bilbao)
        XCTAssertEqual(offset.east, 100, accuracy: 1e-6)
        XCTAssertEqual(offset.north, 200, accuracy: 1e-6)
    }

    // MARK: - Polilíneas

    private let ele = Polyline(points: [
        Vec2(x: 0, z: 0), Vec2(x: 10, z: 0), Vec2(x: 10, z: 20)
    ])

    func testDistanciasAcumuladas() {
        XCTAssertEqual(ele.cumulative, [0, 10, 30])
        XCTAssertEqual(ele.length, 30)
    }

    func testPuntoMasCercanoEnUnSegmento() throws {
        let hit = try XCTUnwrap(ele.nearest(to: Vec2(x: 4, z: -3)))
        XCTAssertEqual(hit.distance, 3, accuracy: 1e-9)
        XCTAssertEqual(hit.chainage, 4, accuracy: 1e-9)
        XCTAssertEqual(hit.segment, 0)
        XCTAssertEqual(hit.point, Vec2(x: 4, z: 0))
    }

    func testPuntoMasCercanoEnElSegundoSegmentoYEnLosExtremos() throws {
        let second = try XCTUnwrap(ele.nearest(to: Vec2(x: 14, z: 15)))
        XCTAssertEqual(second.distance, 4, accuracy: 1e-9)
        XCTAssertEqual(second.chainage, 25, accuracy: 1e-9)
        XCTAssertEqual(second.segment, 1)

        let before = try XCTUnwrap(ele.nearest(to: Vec2(x: -5, z: 0)))
        XCTAssertEqual(before.chainage, 0)
        XCTAssertEqual(before.distance, 5, accuracy: 1e-9)

        let after = try XCTUnwrap(ele.nearest(to: Vec2(x: 10, z: 27)))
        XCTAssertEqual(after.chainage, 30, accuracy: 1e-9)
        XCTAssertEqual(after.distance, 7, accuracy: 1e-9)
    }

    func testPolilineaVaciaODeUnPunto() {
        XCTAssertNil(Polyline(points: []).nearest(to: .zero))
        let single = Polyline(points: [Vec2(x: 3, z: 4)])
        XCTAssertEqual(single.nearest(to: .zero)?.distance, 5)
        XCTAssertEqual(single.point(at: 10), Vec2(x: 3, z: 4))
    }

    func testPuntoYDireccionEnUnaDistanciaRecorrida() {
        XCTAssertEqual(ele.point(at: 5), Vec2(x: 5, z: 0))
        XCTAssertEqual(ele.point(at: 20), Vec2(x: 10, z: 10))
        XCTAssertEqual(ele.point(at: -3), Vec2(x: 0, z: 0), "Se limita al principio")
        XCTAssertEqual(ele.point(at: 99), Vec2(x: 10, z: 20), "Se limita al final")
        XCTAssertEqual(ele.direction(at: 5), Vec2(x: 1, z: 0))
        XCTAssertEqual(ele.direction(at: 20), Vec2(x: 0, z: 1))
        XCTAssertEqual(ele.direction(at: 30), Vec2(x: 0, z: 1))
    }
}
