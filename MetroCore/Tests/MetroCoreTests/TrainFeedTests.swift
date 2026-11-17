import XCTest
@testable import MetroCore

final class TrainFeedTests: XCTestCase {
    // MARK: - Lector protobuf

    func testVarints() throws {
        var reader = ProtoReader(Data([0x01, 0xAC, 0x02, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F]))
        XCTAssertEqual(try reader.readVarint(), 1)
        XCTAssertEqual(try reader.readVarint(), 300)
        XCTAssertEqual(try reader.readVarint(), 0xFFFF_FFFF)
        XCTAssertTrue(reader.isAtEnd)
    }

    func testVarintCortadoOMalFormado() {
        var truncated = ProtoReader(Data([0x80]))
        XCTAssertThrowsError(try truncated.readVarint()) { error in
            XCTAssertEqual(error as? ProtoError, .truncated)
        }
        var endless = ProtoReader(Data([UInt8](repeating: 0x80, count: 11)))
        XCTAssertThrowsError(try endless.readVarint()) { error in
            XCTAssertEqual(error as? ProtoError, .malformedVarint)
        }
    }

    func testCamposFijosYCadenas() throws {
        // Campo 1 (fixed32) = 43.25 en float; campo 2 (cadena) = "7.0".
        var reader = ProtoReader(Data([0x0D, 0x00, 0x00, 0x2D, 0x42, 0x12, 0x03, 0x37, 0x2E, 0x30]))
        var field = try XCTUnwrap(try reader.nextField())
        XCTAssertEqual(field.number, 1)
        XCTAssertEqual(field.wireType, 5)
        XCTAssertEqual(try reader.readFloat(), 43.25)
        field = try XCTUnwrap(try reader.nextField())
        XCTAssertEqual(field.number, 2)
        XCTAssertEqual(field.wireType, 2)
        XCTAssertEqual(try reader.readString(), "7.0")
        XCTAssertNil(try reader.nextField())
    }

    func testUnaLongitudQueSeSaleDelMensajeEsUnError() {
        var reader = ProtoReader(Data([0x12, 0x7F, 0x41]))
        XCTAssertNoThrow(try reader.nextField())
        XCTAssertThrowsError(try reader.readString())
    }

    /// Mensaje montado a mano: cabecera con timestamp y un viaje con un
    /// retraso negativo, que protobuf codifica como varint de diez bytes.
    func testDecodificaRetrasosNegativosYSaltaCamposDesconocidos() throws {
        let stopTimeEvent: [UInt8] = [
            0x08, 0xC4, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, // delay = -60
            0x10, 0xE8, 0x07 // time = 1000
        ]
        let stopTimeUpdate: [UInt8] = [0x08, 0x05, 0x12, UInt8(stopTimeEvent.count)] + stopTimeEvent
            + [0x22, 0x03, 0x37, 0x2E, 0x30] // stop_id = "7.0"
        let trip: [UInt8] = [0x0A, 0x02, 0x54, 0x31, 0x30, 0x02] // trip_id "T1", direction_id 2
        let tripUpdate: [UInt8] = [0x0A, UInt8(trip.count)] + trip
            + [0x12, UInt8(stopTimeUpdate.count)] + stopTimeUpdate
            + [0x32, 0x02, 0x0A, 0x00] // campo 6 desconocido para el decodificador
        let entity: [UInt8] = [0x0A, 0x02, 0x65, 0x31, 0x1A, UInt8(tripUpdate.count)] + tripUpdate
        let header: [UInt8] = [0x0A, 0x03, 0x32, 0x2E, 0x30, 0x18, 0x90, 0x4E] // versión "2.0", timestamp 10000
        let message: [UInt8] = [0x0A, UInt8(header.count)] + header + [0x12, UInt8(entity.count)] + entity

        let feed = try GTFSRealtimeFeed(data: Data(message))
        XCTAssertEqual(feed.timestamp, Date(timeIntervalSince1970: 10000))
        XCTAssertEqual(feed.tripUpdates.count, 1)
        let update = feed.tripUpdates[0]
        XCTAssertEqual(update.entityID, "e1")
        XCTAssertEqual(update.trip.tripID, "T1")
        XCTAssertEqual(update.trip.directionID, 2)
        XCTAssertEqual(update.stopTimes.count, 1)
        XCTAssertEqual(update.stopTimes[0].stopSequence, 5)
        XCTAssertEqual(update.stopTimes[0].stopID, "7.0")
        XCTAssertEqual(update.stopTimes[0].arrivalDelay, -60)
        XCTAssertEqual(update.stopTimes[0].arrival, Date(timeIntervalSince1970: 1000))
        XCTAssertNil(update.stopTimes[0].departure)
    }

    func testUnFicheroCortadoDaError() throws {
        let data = try Fixtures.data("trip-updates.pb")
        XCTAssertThrowsError(try GTFSRealtimeFeed(data: data.prefix(data.count - 7)))
    }

    func testUnFicheroVacioEsUnFeedVacio() throws {
        let feed = try GTFSRealtimeFeed(data: Data())
        XCTAssertNil(feed.timestamp)
        XCTAssertTrue(feed.vehicles.isEmpty)
        XCTAssertTrue(feed.tripUpdates.isEmpty)
    }

    // MARK: - Muestras reales del CTB (descargadas el 17-11-2026)

    func testPosicionesReales() throws {
        let feed = try GTFSRealtimeFeed(data: try Fixtures.data("vehicle-positions.pb"))
        XCTAssertEqual(feed.timestamp, Date(timeIntervalSince1970: 1_794_918_765))
        XCTAssertEqual(feed.vehicles.count, 10)
        XCTAssertTrue(feed.tripUpdates.isEmpty)

        let first = feed.vehicles[0]
        XCTAssertEqual(first.entityID, "PEN_PEN1_KAB_1794918733")
        XCTAssertEqual(first.trip.tripID, "892022")
        XCTAssertEqual(first.trip.routeID, "MB")
        XCTAssertEqual(first.trip.directionID, 1)
        XCTAssertNil(first.trip.startTime)
        XCTAssertEqual(first.vehicleID, "551")
        XCTAssertEqual(first.stopID, "40.0")
        XCTAssertEqual(first.timestamp, Date(timeIntervalSince1970: 1_794_918_733))
        XCTAssertEqual(try XCTUnwrap(first.latitude), 43.32198, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(first.longitude), -3.0254, accuracy: 1e-5)
        XCTAssertTrue(first.hasPosition)
        XCTAssertNil(first.bearing)
        XCTAssertNil(first.status)
        XCTAssertNil(first.currentStopSequence)

        XCTAssertEqual(feed.vehicles.map { $0.stopID }, [
            "40.0", "3.0", "7.0", "8.0", "10.0", "12.0", "17.0", "21.0", "24.0", "37.0"
        ])
        XCTAssertEqual(feed.vehicles[2].trip.directionID, 2)
        XCTAssertEqual(feed.vehicles[2].vehicleID, "606")
    }

    func testActualizacionesDeViajeReales() throws {
        let feed = try GTFSRealtimeFeed(data: try Fixtures.data("trip-updates.pb"))
        XCTAssertEqual(feed.timestamp, Date(timeIntervalSince1970: 1_794_918_765))
        XCTAssertEqual(feed.tripUpdates.count, 70)
        XCTAssertTrue(feed.vehicles.isEmpty)
        XCTAssertEqual(feed.tripUpdates.reduce(0) { $0 + $1.stopTimes.count }, 658)

        let first = feed.tripUpdates[0]
        XCTAssertEqual(first.entityID, "trip_update_891915")
        XCTAssertEqual(first.trip.tripID, "891915")
        XCTAssertEqual(first.trip.routeID, "MB")
        XCTAssertEqual(first.trip.directionID, 2)
        XCTAssertEqual(first.vehicleID, "507")
        XCTAssertEqual(first.timestamp, Date(timeIntervalSince1970: 1_794_918_795))
        XCTAssertEqual(first.stopTimes.prefix(4).map { $0.stopID }, ["25.0", "24.0", "23.0", "22.0"])
        XCTAssertEqual(first.stopTimes[0].arrival, Date(timeIntervalSince1970: 1_794_918_711))
        XCTAssertEqual(first.stopTimes[1].arrival, Date(timeIntervalSince1970: 1_794_918_863))
        XCTAssertNil(first.stopTimes[0].departure)
        XCTAssertNil(first.stopTimes[0].arrivalDelay)
        XCTAssertNil(first.stopTimes[0].stopSequence)

        // Todas las paradas traen hora absoluta de llegada y un stop_id.
        for update in feed.tripUpdates {
            XCTAssertFalse(update.stopTimes.isEmpty)
            for stopTime in update.stopTimes {
                XCTAssertNotNil(stopTime.arrival)
                XCTAssertNotNil(stopTime.stopID)
            }
        }
    }
}
