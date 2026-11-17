import XCTest
@testable import MetroCore

final class SceneTests: XCTestCase {
    private let origin = GeoPoint(latitude: 43.263, longitude: -2.935)

    func testEjesDeLaEscena() {
        let frame = SceneFrame(origin: origin, cotaRef: 18)
        // 111 m al norte, carril a −2 m de cota: 20 m bajo el suelo de referencia.
        let position = frame.position(lon: -2.935, lat: 43.264, cota: -2)
        XCTAssertEqual(position.x, 0, accuracy: 1e-3)
        XCTAssertEqual(position.y, -20, accuracy: 1e-4)
        XCTAssertEqual(position.z, -111.32, accuracy: 0.05)

        let east = frame.position(lon: -2.934, lat: 43.263, cota: 18)
        XCTAssertEqual(east.x, 81.06, accuracy: 0.05)
        XCTAssertEqual(east.y, 0, accuracy: 1e-4)
        XCTAssertEqual(east.z, 0, accuracy: 1e-3)
    }

    func testCarrilYSueloDeUnPuntoDeVia() {
        let frame = SceneFrame(origin: origin, cotaRef: 18)
        let punto = PuntoVia(lon: -2.935, lat: 43.263, cotaCarril: -2.5, cotaSuelo: 19)
        XCTAssertEqual(frame.rail(punto).y, -20.5, accuracy: 1e-4)
        XCTAssertEqual(frame.ground(punto).y, 1, accuracy: 1e-4)
        XCTAssertEqual(frame.height(ofCota: 18), 0)
    }

    func testIdaYVueltaDelPlano() {
        let frame = SceneFrame(origin: origin, cotaRef: 0)
        let point = GeoPoint(latitude: 43.2655, longitude: -2.9301)
        let back = frame.geo(frame.plane(point))
        XCTAssertEqual(back.latitude, point.latitude, accuracy: 1e-10)
        XCTAssertEqual(back.longitude, point.longitude, accuracy: 1e-10)
    }

    func testDireccionDeUnRumbo() {
        let north = SceneFrame.direction(bearing: 0)
        XCTAssertEqual(north.x, 0, accuracy: 1e-6)
        XCTAssertEqual(north.z, -1, accuracy: 1e-6)
        let east = SceneFrame.direction(bearing: 90)
        XCTAssertEqual(east.x, 1, accuracy: 1e-6)
        XCTAssertEqual(east.z, 0, accuracy: 1e-6)
        let south = SceneFrame.direction(bearing: 180)
        XCTAssertEqual(south.z, 1, accuracy: 1e-6)
    }

    // MARK: - Colores

    func testColoresHexadecimales() throws {
        let orange = try XCTUnwrap(ColorHex.rgb("#FF6505"))
        XCTAssertEqual(orange.r, 1, accuracy: 1e-9)
        XCTAssertEqual(orange.g, 101.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(orange.b, 5.0 / 255, accuracy: 1e-9)
        XCTAssertNotNil(ColorHex.rgb("e3007d"))
        XCTAssertNil(ColorHex.rgb("red"))
        XCTAssertNil(ColorHex.rgb("#12345"))
    }

    func testElNegroDeLaL2SeAclaraParaVerseSobreLaCamara() {
        let black = ColorHex.displayRGB("#000000")
        let luminance = 0.2126 * black.r + 0.7152 * black.g + 0.0722 * black.b
        XCTAssertEqual(luminance, 0.45, accuracy: 1e-6)

        // Un color ya claro no cambia.
        let orange = ColorHex.displayRGB("#FF6505")
        XCTAssertEqual(orange.r, 1, accuracy: 1e-9)
        XCTAssertEqual(orange.g, 101.0 / 255, accuracy: 1e-9)

        // Un color oscuro conserva su tono: el magenta de la L3 sigue siendo más rojo que verde.
        let magenta = ColorHex.displayRGB("#E3007D")
        XCTAssertGreaterThan(magenta.r, magenta.b)
        XCTAssertGreaterThan(magenta.b, magenta.g)
    }

    // MARK: - Desvanecido

    func testOpacidadSegunLaDistancia() {
        XCTAssertEqual(SceneFade.alpha(distance: 0), 1)
        XCTAssertEqual(SceneFade.alpha(distance: 150), 1)
        XCTAssertEqual(SceneFade.alpha(distance: 275), 0.56, accuracy: 1e-9)
        XCTAssertEqual(SceneFade.alpha(distance: 400), 0.12, accuracy: 1e-9)
        XCTAssertEqual(SceneFade.alpha(distance: 900), 0.12, accuracy: 1e-9)
    }

    func testBandasDeOpacidad() {
        XCTAssertEqual(SceneFade.band(distance: 10), 0)
        XCTAssertEqual(SceneFade.band(distance: 151), 1)
        XCTAssertEqual(SceneFade.band(distance: 399), 3)
        XCTAssertEqual(SceneFade.band(distance: 1000), 3)
        var previous = 0
        for distance in stride(from: 0.0, through: 500.0, by: 5.0) {
            let band = SceneFade.band(distance: distance)
            XCTAssertGreaterThanOrEqual(band, previous)
            previous = band
        }
        XCTAssertEqual(SceneFade.alpha(band: 0), 1)
        XCTAssertEqual(SceneFade.alpha(band: 3), 0.12, accuracy: 1e-9)
        XCTAssertGreaterThan(SceneFade.alpha(band: 1), SceneFade.alpha(band: 2))
    }
}

final class AdvisoriesTests: XCTestCase {
    func testSinAvisosCuandoTodoVaBien() {
        var input = AdvisoryInput()
        input.gpsAccuracy = 6
        input.headingAccuracy = 10
        input.distanceToTrack = 30
        XCTAssertEqual(Advisories.evaluate(input), [])
    }

    func testUmbralesDelPlan() {
        var input = AdvisoryInput()
        input.gpsAccuracy = 21
        XCTAssertEqual(Advisories.evaluate(input), [.gpsDebil])
        XCTAssertEqual(Advisory.gpsDebil.mensaje, "Señal débil, acércate a una boca y ánclate.")

        input.gpsAccuracy = 20
        XCTAssertEqual(Advisories.evaluate(input), [])

        input.trackingLimited = true
        XCTAssertEqual(Advisories.evaluate(input), [.arLimitado])
        XCTAssertEqual(Advisory.arLimitado.mensaje, "Mueve el móvil despacio y apunta a una zona con detalle.")

        input.trackingLimited = false
        input.headingAccuracy = 26
        XCTAssertEqual(Advisories.evaluate(input), [.brujulaImprecisa])
        XCTAssertEqual(Advisory.brujulaImprecisa.mensaje, "Aléjate de coches o estructuras metálicas.")
    }

    func testLaBrujulaNoImportaSiElGiroSaleDeLaTrayectoria() {
        var input = AdvisoryInput()
        input.headingAccuracy = 40
        input.dependsOnCompass = false
        XCTAssertEqual(Advisories.evaluate(input), [])
    }

    func testInteriorYAnclaje() {
        var input = AdvisoryInput()
        input.gpsAccuracy = 65
        XCTAssertEqual(Advisories.evaluate(input), [.interior])
        input.anchored = true
        XCTAssertEqual(Advisories.evaluate(input), [], "Anclado en una boca, el GPS ya no manda")
    }

    func testSinPermisoSoloSeAvisaDeEso() {
        var input = AdvisoryInput()
        input.hasLocationPermission = false
        input.trackingLimited = true
        input.trainsOffline = true
        XCTAssertEqual(Advisories.evaluate(input), [.sinPermiso])
    }

    func testVariosAvisosALaVez() {
        var input = AdvisoryInput()
        input.reducedAccuracy = true
        input.gpsAccuracy = 30
        input.distanceToTrack = 900
        input.trainsOffline = true
        XCTAssertEqual(Advisories.evaluate(input), [.ubicacionAproximada, .gpsDebil, .lejosDelMetro, .sinTrenes])
    }

    func testTodosLosAvisosTienenMensaje() {
        for advisory in Advisory.allCases {
            XCTAssertFalse(advisory.mensaje.isEmpty)
        }
    }
}

final class DepthMeasurementTests: XCTestCase {
    func testFilaParaDepthsCSV() {
        let measurement = DepthMeasurement(
            stopID: "8", nombre: "Eliptikoa", desnivel: 19.44, cotaBoca: 18.4, fecha: "2026-11-20"
        )
        // Carril = 18,4 − 19,44 − 1,05 de andén (el mismo valor que usa tools/build_network.py).
        XCTAssertEqual(measurement.cotaCarril ?? .nan, -2.09, accuracy: 1e-9)
        XCTAssertEqual(measurement.csvRow, "8,Eliptikoa,-2.1,19.4,18.4,medido,2026-11-20")
        XCTAssertEqual(DepthMeasurement.csvHeader.split(separator: ",").count, 7)
        XCTAssertEqual(measurement.csvRow.split(separator: ",", omittingEmptySubsequences: false).count, 7)
    }

    func testSinCotaDeBocaSeDejanLosHuecos() {
        let measurement = DepthMeasurement(
            stopID: "osm-1", nombre: "Zazpikaleak / Casco Viejo", desnivel: 30, cotaBoca: nil, fecha: "2026-11-20"
        )
        XCTAssertNil(measurement.cotaCarril)
        XCTAssertEqual(measurement.csvRow, "osm-1,Zazpikaleak / Casco Viejo,,30.0,,medido,2026-11-20")
    }

    func testLosNombresConComaVanEntreComillas() {
        let measurement = DepthMeasurement(
            stopID: "1", nombre: "Plaza, la \"grande\"", desnivel: 5, cotaBoca: 10, fecha: "2026-01-02"
        )
        XCTAssertTrue(measurement.csvRow.hasPrefix("1,\"Plaza, la \"\"grande\"\"\","))
    }

    func testFechaDeHoy() {
        let date = Date(timeIntervalSince1970: 1_794_918_765)
        XCTAssertEqual(DepthMeasurement.today(date, timeZone: TimeZone(identifier: "UTC")!), "2026-11-17")
    }
}
