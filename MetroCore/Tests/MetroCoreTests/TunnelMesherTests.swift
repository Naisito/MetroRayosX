import XCTest
@testable import MetroCore

final class TunnelMesherTests: XCTestCase {
    /// Camino recto hacia el norte (−z), un punto cada 5 m, a 20 m bajo el suelo.
    private func northPath(points: Int, startZ: Float = 0) -> [Vec3] {
        (0..<points).map { Vec3(0, -20, startZ - Float($0) * 5) }
    }

    private func assertValid(_ mesh: MeshData, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(mesh.indices.count % 3, 0, file: file, line: line)
        let count = UInt32(mesh.positions.count)
        XCTAssertTrue(mesh.indices.allSatisfy { $0 < count }, "Índice fuera de rango", file: file, line: line)
        for position in mesh.positions {
            XCTAssertTrue(position.x.isFinite && position.y.isFinite && position.z.isFinite, file: file, line: line)
        }
    }

    // MARK: - Primitivas

    func testUnCuadradoSonCuatroVerticesYDosCarasDobles() {
        var mesh = MeshData()
        mesh.addQuad(Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(1, 0, 1), Vec3(0, 0, 1))
        XCTAssertEqual(mesh.positions.count, 4)
        XCTAssertEqual(mesh.triangleCount, 4, "Dos triángulos por cada cara")
        assertValid(mesh)
    }

    func testUnirMallasDesplazaLosIndices() {
        var a = MeshData()
        a.addQuad(Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(1, 0, 1), Vec3(0, 0, 1))
        var b = a
        b.append(a)
        XCTAssertEqual(b.positions.count, 8)
        XCTAssertEqual(b.indices.max(), 7)
        assertValid(b)
    }

    func testLaCintaSigueElCaminoConSuAncho() {
        var mesh = MeshData()
        mesh.addRibbon(path: northPath(points: 5), width: 2, lateral: 3, lift: 1)
        XCTAssertEqual(mesh.positions.count, 10)
        XCTAssertEqual(mesh.triangleCount, 4 * 4)
        assertValid(mesh)
        // Yendo al norte, la derecha es el este (+x): centro en x = 3, de 2 a 4.
        for (i, position) in mesh.positions.enumerated() {
            XCTAssertEqual(position.x, i % 2 == 0 ? 2 : 4, accuracy: 1e-5)
            XCTAssertEqual(position.y, -19, accuracy: 1e-5)
        }
    }

    func testLaCintaNecesitaDosPuntos() {
        var mesh = MeshData()
        mesh.addRibbon(path: [Vec3(0, 0, 0)], width: 1)
        XCTAssertTrue(mesh.isEmpty)
    }

    func testBarraHorizontalYVertical() {
        var horizontal = MeshData()
        horizontal.addBar(from: Vec3(0, 0, 0), to: Vec3(10, 0, 0), thickness: 0.2)
        XCTAssertEqual(horizontal.positions.count, 16)
        assertValid(horizontal)
        for position in horizontal.positions {
            XCTAssertEqual(abs(position.y), 0.1, accuracy: 1e-5)
            XCTAssertEqual(abs(position.z), 0.1, accuracy: 1e-5)
        }

        var vertical = MeshData()
        vertical.addBar(from: Vec3(5, 0, 5), to: Vec3(5, -20, 5), thickness: 0.2)
        assertValid(vertical)
        for position in vertical.positions {
            XCTAssertEqual(abs(position.x - 5), 0.1, accuracy: 1e-5)
            XCTAssertEqual(abs(position.z - 5), 0.1, accuracy: 1e-5)
        }

        var empty = MeshData()
        empty.addBar(from: Vec3(1, 1, 1), to: Vec3(1, 1, 1), thickness: 0.2)
        XCTAssertTrue(empty.isEmpty)
    }

    func testElAnilloEsPerpendicularALaVia() {
        var mesh = MeshData()
        let center = Vec3(10, -18, -50)
        mesh.addRing(center: center, tangent: Vec3(0, 0, -1), radius: 3, segments: 16, width: 0.4)
        XCTAssertEqual(mesh.positions.count, 32)
        XCTAssertEqual(mesh.triangleCount, 16 * 4)
        assertValid(mesh)
        for position in mesh.positions {
            let dx = position.x - center.x
            let dy = position.y - center.y
            XCTAssertEqual((dx * dx + dy * dy).squareRoot(), 3, accuracy: 1e-4, "Radio en el plano x-y")
            XCTAssertEqual(abs(position.z - center.z), 0.2, accuracy: 1e-5, "Medio ancho a cada lado")
        }
    }

    func testCajaYCajaDeAlambre() {
        var box = MeshData()
        box.addBox(center: Vec3(0, -10, 0), direction: Vec3(0, 0, -1), length: 18, width: 2.6, height: 3.4)
        XCTAssertEqual(box.positions.count, 24)
        assertValid(box)
        XCTAssertEqual(box.positions.map { $0.y }.min() ?? 0, -10, accuracy: 1e-5)
        XCTAssertEqual(box.positions.map { $0.y }.max() ?? 0, -6.6, accuracy: 1e-5)
        XCTAssertEqual(box.positions.map { $0.z }.min() ?? 0, -9, accuracy: 1e-5)
        XCTAssertEqual(box.positions.map { $0.x }.max() ?? 0, 1.3, accuracy: 1e-5)

        var wire = MeshData()
        wire.addWireBox(
            center: Vec3(0, 0, 0), direction: Vec3(1, 0, 0), length: 90, width: 16, height: 7, thickness: 0.3
        )
        XCTAssertEqual(wire.positions.count, 12 * 16, "Doce aristas")
        assertValid(wire)
    }

    func testLaCoronaEsHorizontal() {
        var mesh = MeshData()
        mesh.addAnnulus(center: Vec3(1, 2, 3), inner: 2, outer: 2.2, segments: 24)
        XCTAssertEqual(mesh.positions.count, 48)
        assertValid(mesh)
        for position in mesh.positions {
            XCTAssertEqual(position.y, 2, accuracy: 1e-6)
            let dx = position.x - 1
            let dz = position.z - 3
            let radius = (dx * dx + dz * dz).squareRoot()
            XCTAssertTrue(abs(radius - 2) < 1e-4 || abs(radius - 2.2) < 1e-4)
        }
    }

    // MARK: - Vías

    func testEnTunelHayCarrilesBalastoYEstructura() {
        let mesh = TunnelMesher.track(path: northPath(points: 21), startChainage: 0, tunnel: true, tracks: 1)
        XCTAssertFalse(mesh.rails.isEmpty)
        XCTAssertFalse(mesh.bed.isEmpty)
        XCTAssertFalse(mesh.structure.isEmpty)
        assertValid(mesh.rails)
        assertValid(mesh.bed)
        assertValid(mesh.structure)

        // Dos carriles: dos cintas de 21 puntos.
        XCTAssertEqual(mesh.rails.positions.count, 2 * 21 * 2)
        // Vía métrica: los carriles están a ±0,5 m del eje (más el medio ancho del carril).
        let style = TunnelStyle()
        let xs = Set(mesh.rails.positions.map { Int(($0.x * 100).rounded()) }).sorted()
        let half = Int((style.railWidth * 50).rounded())
        XCTAssertEqual(xs, [-50 - half, -50 + half, 50 - half, 50 + half])
    }

    func testEnSuperficieNoHayAnillos() {
        let mesh = TunnelMesher.track(path: northPath(points: 21), startChainage: 0, tunnel: false, tracks: 1)
        XCTAssertFalse(mesh.rails.isEmpty)
        XCTAssertTrue(mesh.structure.isEmpty)
    }

    func testDosPistasDuplicanLosCarriles() {
        let one = TunnelMesher.track(path: northPath(points: 11), startChainage: 0, tunnel: true, tracks: 1)
        let two = TunnelMesher.track(path: northPath(points: 11), startChainage: 0, tunnel: true, tracks: 2)
        XCTAssertEqual(two.rails.positions.count, one.rails.positions.count * 2)
        XCTAssertEqual(two.structure.positions.count, one.structure.positions.count * 2)
        let style = TunnelStyle()
        let maxX = two.bed.positions.map { $0.x }.max() ?? 0
        XCTAssertEqual(maxX, style.trackSpacing / 2 + style.bedWidth / 2, accuracy: 1e-4)
    }

    func testUnAnilloCadaDiezMetros() {
        let rings = TunnelMesher.ringPositions(path: northPath(points: 21), startChainage: 0, spacing: 10)
        // 100 m de tramo: anillos en 0, 10, ..., 90 (el de 100 es del tramo siguiente).
        XCTAssertEqual(rings.count, 10)
        for (i, ring) in rings.enumerated() {
            XCTAssertEqual(ring.point.z, -Float(i) * 10, accuracy: 1e-3)
            XCTAssertEqual(ring.tangent.z, -1, accuracy: 1e-5)
        }
    }

    func testLosAnillosNoSeRepitenNiSeSaltanEntreTramos() {
        // Una vía de 250 m partida en tramos que no empiezan en múltiplos de 10.
        let first = TunnelMesher.ringPositions(path: northPath(points: 16), startChainage: 0, spacing: 10)
        let second = TunnelMesher.ringPositions(
            path: northPath(points: 16, startZ: -75), startChainage: 75, spacing: 10
        )
        let third = TunnelMesher.ringPositions(
            path: northPath(points: 21, startZ: -150), startChainage: 150, spacing: 10
        )
        let all = (first + second + third).map { Double(-$0.point.z) }
        XCTAssertEqual(all.count, 25)
        for (i, z) in all.enumerated() {
            XCTAssertEqual(z, Double(i) * 10, accuracy: 1e-2)
        }
    }

    func testMallaDeUnTramoRealDeLaRed() throws {
        let model = try Fixtures.realModel()
        let estacion = try XCTUnwrap(model.red.estaciones.first { $0.nombre == "Eliptikoa" })
        let ground = try XCTUnwrap(model.groundElevation(at: estacion.geo))
        let frame = SceneFrame(origin: estacion.geo, cotaRef: ground)
        let chunks = model.chunks(near: estacion.geo, radius: 400)
        XCTAssertFalse(chunks.isEmpty)

        var triangles = 0
        for chunk in chunks {
            let via = model.red.vias[chunk.key.via]
            let path = chunk.puntos.map { frame.rail($0) }
            let mesh = TunnelMesher.track(
                path: path, startChainage: chunk.startChainage, tunnel: via.tunel, tracks: via.pistas
            )
            assertValid(mesh.rails)
            assertValid(mesh.bed)
            assertValid(mesh.structure)
            triangles += mesh.rails.triangleCount + mesh.bed.triangleCount + mesh.structure.triangleCount
            // Bajo Moyua todo va en túnel y por debajo del suelo de referencia.
            for position in mesh.rails.positions {
                XCTAssertLessThan(position.y, 0)
                // Un tramo entra si toca el radio de 400 m y mide hasta 100 m.
                XCTAssertLessThan(abs(position.x), 520)
                XCTAssertLessThan(abs(position.z), 520)
            }
        }
        XCTAssertGreaterThan(triangles, 1000)
        XCTAssertLessThan(triangles, 400_000, "Demasiados triángulos para 60 imágenes por segundo")
    }

    // MARK: - Rejilla del suelo

    func testLaRejillaDejaUnaVentanaBajoLosPies() {
        let bands = TunnelMesher.groundGrid(userX: 3.2, userZ: -7.9, y: 0, radius: 30, spacing: 2.5, hole: 2.5)
        XCTAssertEqual(bands.count, 3)
        for band in bands {
            XCTAssertFalse(band.isEmpty)
            assertValid(band)
            for position in band.positions {
                XCTAssertEqual(position.y, 0)
                let dx = position.x - 3.2
                let dz = position.z + 7.9
                let distance = (dx * dx + dz * dz).squareRoot()
                XCTAssertGreaterThan(distance, 1.0, "Ninguna línea cruza la ventana")
                XCTAssertLessThan(distance, 32.0)
            }
        }
    }

    func testLasLineasDeLaRejillaNoSeMuevenAlAndar() {
        // Los ejes de las líneas caen siempre en múltiplos del paso.
        func lineCenters(userX: Float) -> Set<Int> {
            let bands = TunnelMesher.groundGrid(userX: userX, userZ: 0, y: 0, radius: 10, spacing: 2.5, hole: 1)
            var centers = Set<Int>()
            for band in bands {
                var i = 0
                while i + 3 < band.positions.count {
                    let quad = band.positions[i...(i + 3)]
                    let xs = quad.map { $0.x }
                    let width = (xs.max() ?? 0) - (xs.min() ?? 0)
                    if width < 0.5 {
                        // Línea norte-sur: su eje x es el centro del cuadrado.
                        let center = ((xs.max() ?? 0) + (xs.min() ?? 0)) / 2
                        centers.insert(Int((center * 10).rounded()))
                    }
                    i += 4
                }
            }
            return centers
        }
        let here = lineCenters(userX: 0)
        let moved = lineCenters(userX: 1.3)
        XCTAssertFalse(here.isEmpty)
        for center in here.union(moved) {
            XCTAssertEqual(center % 25, 0, "Eje en x = \(Double(center) / 10)")
        }
        XCTAssertFalse(here.intersection(moved).isEmpty)
    }
}
