import XCTest
@testable import MetroCore

final class FileLogTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLogTests-\(UUID().uuidString)")
        fileURL = directory.appendingPathComponent("registro.log")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeLog(maxBytes: Int = 1_000_000) -> FileLog {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 17
        components.hour = 12
        components.minute = 30
        components.second = 5
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let fixedDate = calendar.date(from: components)!

        return FileLog(
            fileURL: fileURL,
            maxBytes: maxBytes,
            timeZone: TimeZone(identifier: "UTC")!,
            now: { fixedDate }
        )
    }

    func testEscribeUnaLineaConFechaYCategoria() {
        let log = makeLog()
        let line = log.write("hola", category: "gps")
        XCTAssertEqual(line, "2026-11-17 12:30:05.000 [gps] hola")
        XCTAssertEqual(log.readAll(), "2026-11-17 12:30:05.000 [gps] hola\n")
    }

    func testLaCategoriaPorDefectoEsApp() {
        let log = makeLog()
        XCTAssertTrue(log.write("arranque").hasSuffix("[app] arranque"))
    }

    func testCreaLaCarpetaSiNoExiste() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        makeLog().write("primera")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testAnadeLineasSinBorrarLasAnteriores() {
        let log = makeLog()
        log.write("uno")
        log.write("dos")
        log.write("tres")
        let lines = log.tail(lines: 10)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasSuffix("uno"))
        XCTAssertTrue(lines[2].hasSuffix("tres"))
    }

    func testTailDevuelveSoloLasUltimas() {
        let log = makeLog()
        for index in 1...10 {
            log.write("linea \(index)")
        }
        let lines = log.tail(lines: 3)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasSuffix("linea 8"))
        XCTAssertTrue(lines[2].hasSuffix("linea 10"))
    }

    func testUnMensajeDeVariasLineasOcupaUnaSola() {
        let log = makeLog()
        log.write("primera\nsegunda\r\ntercera")
        let lines = log.tail(lines: 10)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].hasSuffix("primera | segunda | tercera"))
    }

    func testUnSegundoRegistroContinuaElMismoFichero() {
        makeLog().write("sesion 1")
        let second = makeLog()
        second.write("sesion 2")
        XCTAssertEqual(second.tail(lines: 10).count, 2)
    }

    func testVaciarBorraElContenido() {
        let log = makeLog()
        log.write("algo")
        log.clear()
        XCTAssertEqual(log.readAll(), "")
        XCTAssertEqual(log.tail(lines: 5), [])
        log.write("de nuevo")
        XCTAssertEqual(log.tail(lines: 5).count, 1)
    }

    func testRecortaElFicheroCuandoSuperaElMaximo() throws {
        let maxBytes = 2000
        let log = makeLog(maxBytes: maxBytes)
        for index in 1...300 {
            log.write("mensaje número \(index) con algo de relleno")
        }

        let data = try Data(contentsOf: fileURL)
        XCTAssertLessThanOrEqual(data.count, maxBytes)
        XCTAssertGreaterThan(data.count, maxBytes / 4)

        let lines = log.tail(lines: 1000)
        XCTAssertTrue(lines.last?.hasSuffix("mensaje número 300 con algo de relleno") ?? false)
        // El recorte empieza en un principio de línea: todas conservan la fecha.
        for line in lines {
            XCTAssertTrue(line.hasPrefix("2026-11-17 12:30:05.000 [app] mensaje número "), line)
        }
    }

    func testEscriturasDesdeVariosHilosNoPierdenLineas() {
        let log = makeLog()
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            log.write("hilo \(index)")
        }
        XCTAssertEqual(log.tail(lines: 1000).count, 200)
    }
}
