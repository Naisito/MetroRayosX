import XCTest
@testable import MetroCore

final class GeoFormatTests: XCTestCase {
    func testGradosConSeisDecimales() {
        XCTAssertEqual(GeoFormat.degrees(43.2631), "43.263100°")
        XCTAssertEqual(GeoFormat.degrees(-2.935), "-2.935000°")
    }

    func testMetrosPorDebajoDeUnKilometro() {
        XCTAssertEqual(GeoFormat.meters(8.4), "8 m")
        XCTAssertEqual(GeoFormat.meters(0), "0 m")
        XCTAssertEqual(GeoFormat.meters(999.4), "999 m")
    }

    func testKilometrosConComaDecimal() {
        XCTAssertEqual(GeoFormat.meters(1234), "1,2 km")
        XCTAssertEqual(GeoFormat.meters(15_000), "15,0 km")
    }

    func testPuntosCardinales() {
        XCTAssertEqual(GeoFormat.cardinal(0), "N")
        XCTAssertEqual(GeoFormat.cardinal(44), "NE")
        XCTAssertEqual(GeoFormat.cardinal(90), "E")
        XCTAssertEqual(GeoFormat.cardinal(135), "SE")
        XCTAssertEqual(GeoFormat.cardinal(180), "S")
        XCTAssertEqual(GeoFormat.cardinal(225), "SO")
        XCTAssertEqual(GeoFormat.cardinal(270), "O")
        XCTAssertEqual(GeoFormat.cardinal(315), "NO")
    }

    func testPuntosCardinalesEnLosBordes() {
        XCTAssertEqual(GeoFormat.cardinal(22.4), "N")
        XCTAssertEqual(GeoFormat.cardinal(22.6), "NE")
        XCTAssertEqual(GeoFormat.cardinal(359), "N")
        XCTAssertEqual(GeoFormat.cardinal(360), "N")
        XCTAssertEqual(GeoFormat.cardinal(-90), "O")
        XCTAssertEqual(GeoFormat.cardinal(720 + 180), "S")
    }
}
