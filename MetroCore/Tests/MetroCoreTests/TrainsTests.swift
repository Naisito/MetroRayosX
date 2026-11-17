import XCTest
@testable import MetroCore

final class TrainsTests: XCTestCase {
    private let model = TestNetwork.model()
    private var locator: TrainLocator {
        TrainLocator(model: model)
    }

    private func date(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: 1_000_000 + seconds)
    }

    /// Viaje con llegadas absolutas, como las del feed real (sin hora de salida).
    private func update(_ id: String, stops: [(String, Double)], direction: Int? = nil) -> RTTripUpdate {
        RTTripUpdate(
            entityID: "trip_update_" + id,
            trip: RTTrip(tripID: id, routeID: "MB", directionID: direction),
            stopTimes: stops.map { RTStopTime(stopID: $0.0, arrival: date($0.1)) }
        )
    }

    // Estaciones de la red de prueba en la ruta L1-0: "1" en 100 m, "2" en 600 m, "3" en 1450 m.

    func testEntreDosParadasSeInterpola() throws {
        let trip = update("t", stops: [("1.0", 0), ("2.0", 120), ("3.0", 300)])
        // Sale de "1" a los 20 s (parada por defecto) y llega a "2" a los 120 s: mitad de camino a los 70 s.
        let train = try XCTUnwrap(locator.locate(update: trip, now: date(70)))
        XCTAssertEqual(train.id, "t")
        XCTAssertEqual(model.rutas[train.rutaIndex].ruta.id, "L1-0")
        XCTAssertEqual(train.chainage, 350, accuracy: 0.5)
        XCTAssertFalse(train.detenido)
        XCTAssertEqual(train.estacionID, "2")
        XCTAssertEqual(train.linea, "L1")
    }

    func testArrancaYFrenaConSuavidad() throws {
        let trip = update("t", stops: [("1.0", 0), ("2.0", 120)])
        let early = try XCTUnwrap(locator.locate(update: trip, now: date(30)))
        let late = try XCTUnwrap(locator.locate(update: trip, now: date(110)))
        // A un 10 % del tiempo lleva menos del 10 % del recorrido, y al revés al final.
        XCTAssertLessThan(early.chainage, 100 + 500 * 0.1)
        XCTAssertGreaterThan(early.chainage, 100)
        XCTAssertGreaterThan(late.chainage, 100 + 500 * 0.9)
        XCTAssertLessThan(late.chainage, 600)
    }

    func testLaPosicionAvanzaSinSaltos() throws {
        let trip = update("t", stops: [("1.0", 0), ("2.0", 120), ("3.0", 300)])
        var previous = -1.0
        for second in stride(from: 0.0, through: 300.0, by: 1.0) {
            let train = try XCTUnwrap(locator.locate(update: trip, now: date(second)))
            XCTAssertGreaterThanOrEqual(train.chainage, previous)
            if previous >= 0 {
                XCTAssertLessThan(train.chainage - previous, 25, "Salto en t = \(second)")
            }
            previous = train.chainage
        }
        XCTAssertEqual(previous, 1450, accuracy: 0.5)
    }

    func testParadoEnLaEstacion() throws {
        let trip = update("t", stops: [("1.0", 0), ("2.0", 120), ("3.0", 300)])
        let train = try XCTUnwrap(locator.locate(update: trip, now: date(130)))
        XCTAssertEqual(train.chainage, 600, accuracy: 0.5)
        XCTAssertTrue(train.detenido)
        XCTAssertEqual(train.estacionID, "2")
    }

    func testAntesDeLaPrimeraParadaVieneDeLaEstacionAnterior() throws {
        // Solo queda por anunciar "3"; la anterior en la ruta es "2", a 850 m (unos 71 s).
        let trip = update("t", stops: [("3.0", 100)])
        let midway = try XCTUnwrap(locator.locate(update: trip, now: date(100 - 35.4)))
        XCTAssertEqual(midway.chainage, (600 + 1450) / 2, accuracy: 5)
        XCTAssertFalse(midway.detenido)

        let waiting = try XCTUnwrap(locator.locate(update: trip, now: date(100 - 100)))
        XCTAssertEqual(waiting.chainage, 600, accuracy: 0.5)
        XCTAssertTrue(waiting.detenido)

        XCTAssertNil(locator.locate(update: trip, now: date(100 - 400)), "Aún no ha salido de cabecera")
    }

    func testUnViajeTerminadoDesaparece() throws {
        let trip = update("t", stops: [("2.0", 0), ("3.0", 100)])
        let arrived = try XCTUnwrap(locator.locate(update: trip, now: date(110)))
        XCTAssertEqual(arrived.chainage, 1450, accuracy: 0.5)
        XCTAssertTrue(arrived.detenido)
        XCTAssertNil(locator.locate(update: trip, now: date(100 + 46)))
    }

    func testElSentidoSaleDelOrdenDeLasParadas() throws {
        let trip = update("vuelta", stops: [("3.0", 0), ("2.0", 150), ("1.0", 260)])
        let train = try XCTUnwrap(locator.locate(update: trip, now: date(85)))
        XCTAssertEqual(model.rutas[train.rutaIndex].ruta.id, "L1-1")
        // En L1-1, "3" está en 50 m y "2" en 900 m.
        XCTAssertEqual(train.chainage, (50 + 900) / 2, accuracy: 1)
    }

    func testConUnaSolaParadaElDirectionIdDesempata() throws {
        // Llegando a "2" desde cualquiera de los dos lados: decide direction_id.
        let towardsNorth = update("a", stops: [("2.0", 60)], direction: 1)
        let towardsWest = update("b", stops: [("2.0", 60)], direction: 2)
        let a = try XCTUnwrap(locator.locate(update: towardsNorth, now: date(50)))
        let b = try XCTUnwrap(locator.locate(update: towardsWest, now: date(50)))
        XCTAssertEqual(model.rutas[a.rutaIndex].ruta.id, "L1-0")
        XCTAssertEqual(model.rutas[b.rutaIndex].ruta.id, "L1-1")
    }

    func testUnaParadaFueraDeSitioSeCambiaPorLaQueFalta() throws {
        // Como Urduliz en el feed real: la parada del medio llega con el id de otra estación.
        let trip = update("t", stops: [("1.0", 0), ("1.0", 120), ("3.0", 300)])
        let train = try XCTUnwrap(locator.locate(update: trip, now: date(125)))
        XCTAssertEqual(train.chainage, 600, accuracy: 0.5, "La parada repetida se trata como la estación 2")
        XCTAssertEqual(train.estacionID, "2")
        XCTAssertTrue(train.detenido)
    }

    func testLasParadasDesconocidasSeIgnoran() {
        let trip = update("t", stops: [("99.0", 0), ("98.0", 100)])
        XCTAssertNil(locator.locate(update: trip, now: date(50)))
        XCTAssertNil(locator.locate(update: update("vacio", stops: []), now: date(0)))
    }

    func testLasPosicionesSoloRellenanLosTrenesSinHorario() {
        let trip = update("t", stops: [("1.0", 0), ("2.0", 120)])
        var stopped = RTVehicle(entityID: "v1", trip: RTTrip(tripID: "t", routeID: "MB", directionID: 1))
        stopped.stopID = "1.0"
        var other = RTVehicle(entityID: "v2", trip: RTTrip(tripID: "otro", routeID: "MB", directionID: 2))
        other.stopID = "3.0"
        let station3 = model.red.estaciones[2]
        other.latitude = station3.lat
        other.longitude = station3.lon

        let trains = locator.locate(tripUpdates: [trip], vehicles: [stopped, other], now: date(70))
        XCTAssertEqual(trains.map { $0.id }, ["otro", "t"])
        XCTAssertEqual(trains[1].chainage, 350, accuracy: 0.5, "Manda el horario, no la posición parada")
        XCTAssertEqual(model.rutas[trains[0].rutaIndex].ruta.id, "L1-1")
        XCTAssertEqual(trains[0].chainage, 50, accuracy: 1)
        XCTAssertTrue(trains[0].detenido)
    }

    func testIdentificadorDeLinea() {
        var locator = self.locator
        XCTAssertNil(locator.lineID(forRoute: "MB"))
        XCTAssertEqual(locator.lineID(forRoute: "l1-norte"), "L1")
        locator.routeToLine = ["MB": "L1"]
        XCTAssertEqual(locator.lineID(forRoute: "MB"), "L1")
        XCTAssertNil(locator.lineID(forRoute: nil))
    }

    func testDiferenciaDeRumbos() {
        XCTAssertEqual(TrainLocator.angleDifference(350, 10), -20)
        XCTAssertEqual(TrainLocator.angleDifference(10, 350), 20)
        XCTAssertEqual(TrainLocator.angleDifference(180, 0), 180)
    }

    // MARK: - Feed real sobre la red real

    func testLosViajesRealesSeColocanSobreLaRedReal() throws {
        let real = try Fixtures.realModel()
        let feed = try GTFSRealtimeFeed(data: try Fixtures.data("trip-updates.pb"))
        let vehicles = try GTFSRealtimeFeed(data: try Fixtures.data("vehicle-positions.pb"))
        let locator = TrainLocator(model: real)
        let now = try XCTUnwrap(feed.timestamp)

        // Todas las paradas del feed existen en la red.
        for update in feed.tripUpdates {
            for stopTime in update.stopTimes {
                let stopID = try XCTUnwrap(stopTime.stopID)
                XCTAssertNotNil(real.station(forStop: stopID), "Parada desconocida: \(stopID)")
            }
        }

        let trains = locator.locate(tripUpdates: feed.tripUpdates, vehicles: vehicles.vehicles, now: now)
        // De los 70 viajes anunciados, muchos aún no han salido de cabecera.
        XCTAssertGreaterThan(trains.count, 15, "Trenes en circulación a la hora del feed")
        XCTAssertLessThanOrEqual(trains.count, 70)
        XCTAssertEqual(Set(trains.map { $0.id }).count, trains.count)

        for train in trains {
            let route = real.rutas[train.rutaIndex]
            XCTAssertTrue(["L1", "L2"].contains(route.ruta.linea), "El feed solo trae L1 y L2")
            XCTAssertGreaterThanOrEqual(train.chainage, 0)
            XCTAssertLessThanOrEqual(train.chainage, route.length)
        }

        // Los trenes que el feed de posiciones da como parados en una estación
        // deben salir cerca de ella.
        var compared = 0
        for vehicle in vehicles.vehicles {
            guard let tripID = vehicle.trip.tripID,
                  let train = trains.first(where: { $0.id == tripID }),
                  let latitude = vehicle.latitude, let longitude = vehicle.longitude
            else {
                continue
            }
            let position = real.rutas[train.rutaIndex].point(at: train.chainage).geo
            let distance = Geo.distance(from: position, to: GeoPoint(latitude: latitude, longitude: longitude))
            XCTAssertLessThan(distance, 900, "Tren \(tripID) lejos de donde el feed lo da parado")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 5)
    }

    func testLosTrenesRealesSeMuevenConElReloj() throws {
        let real = try Fixtures.realModel()
        let feed = try GTFSRealtimeFeed(data: try Fixtures.data("trip-updates.pb"))
        let locator = TrainLocator(model: real)
        let now = try XCTUnwrap(feed.timestamp)

        var moved = 0
        for update in feed.tripUpdates {
            guard let before = locator.locate(update: update, now: now),
                  let after = locator.locate(update: update, now: now.addingTimeInterval(30))
            else {
                continue
            }
            XCTAssertEqual(before.rutaIndex, after.rutaIndex)
            let advance = after.chainage - before.chainage
            XCTAssertGreaterThanOrEqual(advance, -0.001, "Un tren no retrocede")
            XCTAssertLessThan(advance, 30 * 30, "Más de 108 km/h en el viaje \(before.id)")
            if advance > 1 {
                moved += 1
            }
        }
        XCTAssertGreaterThan(moved, 10)
    }
}
