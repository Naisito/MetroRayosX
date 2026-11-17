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

    func testLaDistanciaEsSimetrica() {
        let a = Landmarks.moyua.point
        let b = Landmarks.cascoViejo.point
        let ida = Geo.distance(from: a, to: b)
        let vuelta = Geo.distance(from: b, to: a)
        XCTAssertEqual(ida, vuelta, accuracy: 0.01)
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
}
