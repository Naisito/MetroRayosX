import Foundation
import XCTest
@testable import MetroCore

/// Generador de números aleatorios con semilla (SplitMix64), para que los
/// tests con ruido den siempre lo mismo.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniforme en [0, 1).
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Punto uniforme dentro de un círculo de radio `radius`.
    mutating func inDisc(radius: Double) -> Vec2 {
        let r = radius * unit().squareRoot()
        let angle = unit() * 2 * .pi
        return Vec2(x: r * cos(angle), z: r * sin(angle))
    }
}

enum Fixtures {
    static var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    /// Carpeta `App/Resources` del repositorio, con los datos reales.
    static var appResources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MetroCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // MetroCore
            .deletingLastPathComponent() // raíz del repositorio
            .appendingPathComponent("App")
            .appendingPathComponent("Resources")
    }

    /// La red real, o `XCTSkip` si los datos no están generados.
    static func realModel() throws -> MetroModel {
        let json = appResources.appendingPathComponent("metro.json")
        guard FileManager.default.fileExists(atPath: json.path) else {
            throw XCTSkip("No está App/Resources/metro.json")
        }
        return try NetworkLoader.load(
            jsonURL: json,
            relieveURL: appResources.appendingPathComponent("relieve.bin")
        )
    }
}

/// Red de juguete para los tests.
///
/// Una línea «L1» con una vía en túnel de 1000 m hacia el este (suelo a 20 m,
/// carril a 0 m) seguida de una vía en superficie de 500 m hacia el norte, y
/// tres estaciones. Las rutas L1-0 y L1-1 la recorren en los dos sentidos.
enum TestNetwork {
    static let origin = GeoPoint(latitude: 43.26, longitude: -2.93)
    static let frame = LocalFrame(origin: origin)

    /// Coordenadas geográficas de un punto a `east` y `north` metros del origen.
    static func geo(east: Double, north: Double) -> GeoPoint {
        frame.geo(Vec2(x: east, z: -north))
    }

    static func punto(east: Double, north: Double, carril: Double, suelo: Double) -> PuntoVia {
        let point = geo(east: east, north: north)
        return PuntoVia(lon: point.longitude, lat: point.latitude, cotaCarril: carril, cotaSuelo: suelo)
    }

    static func make() -> Red {
        var tunnel: [PuntoVia] = []
        for i in 0...200 {
            tunnel.append(punto(east: Double(i) * 5, north: 0, carril: 0, suelo: 20))
        }
        var surface: [PuntoVia] = []
        for i in 0...100 {
            let north = Double(i) * 5
            // Sube de 0 m a 20 m en los primeros 400 m y luego va por el suelo.
            let rail = min(north / 400 * 20, 20)
            surface.append(punto(east: 1000, north: north, carril: rail, suelo: 20))
        }

        func estacion(_ id: String, _ nombre: String, east: Double, north: Double, carril: Double, sub: Bool) -> Estacion {
            let point = geo(east: east, north: north)
            let boca = geo(east: east + 10, north: north + 30)
            return Estacion(
                id: id,
                nombre: nombre,
                lat: point.latitude,
                lon: point.longitude,
                cotaCarril: carril,
                cotaSuelo: 20,
                subterranea: sub,
                origenCota: sub ? .estimado : .medido,
                lineas: ["L1"],
                paradas: [id, id + ".0"],
                bocas: [Boca(nombre: "Boca " + nombre, lat: boca.latitude, lon: boca.longitude, cotaSuelo: 20)]
            )
        }

        return Red(
            version: 1,
            generado: "2026-11-17",
            atribucion: ["test"],
            lineas: [Linea(id: "L1", nombre: "Línea de prueba", color: "#FF6505")],
            vias: [
                Via(id: "tunel", lineas: ["L1"], tunel: true, pistas: 1, puntos: tunnel),
                Via(id: "superficie", lineas: ["L1"], tunel: false, pistas: 1, puntos: surface)
            ],
            rutas: [
                Ruta(id: "L1-0", linea: "L1", nombre: "Oeste → Norte", tramos: [
                    TramoRuta(via: "tunel", inv: false),
                    TramoRuta(via: "superficie", inv: false)
                ]),
                Ruta(id: "L1-1", linea: "L1", nombre: "Norte → Oeste", tramos: [
                    TramoRuta(via: "superficie", inv: true),
                    TramoRuta(via: "tunel", inv: true)
                ])
            ],
            estaciones: [
                estacion("1", "Oeste", east: 100, north: 0, carril: 0, sub: true),
                estacion("2", "Centro", east: 600, north: 0, carril: 0, sub: true),
                estacion("3", "Norte", east: 1000, north: 450, carril: 20, sub: false)
            ],
            relieve: nil
        )
    }

    static func model() -> MetroModel {
        MetroModel(red: make(), terrain: nil)
    }
}
