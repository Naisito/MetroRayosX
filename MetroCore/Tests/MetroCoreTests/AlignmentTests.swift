import XCTest
@testable import MetroCore

final class AlignmentTests: XCTestCase {
    private func degrees(_ value: Double) -> Double {
        value * .pi / 180
    }

    /// Trayectoria en L: `legs` metros al este y otros tantos al norte.
    private func walk(samples: Int, leg: Double) -> [Vec2] {
        (0..<samples).map { i in
            let d = Double(i) / Double(samples - 1) * 2 * leg
            return d <= leg ? Vec2(x: d, z: 0) : Vec2(x: leg, z: -(d - leg))
        }
    }

    // MARK: - Convención de signos

    func testElGiroPositivoLlevaElEsteHaciaElSur() {
        let rotated = RigidTransform2D.rotate(Vec2(x: 1, z: 0), by: degrees(90))
        XCTAssertEqual(rotated.x, 0, accuracy: 1e-12)
        XCTAssertEqual(rotated.z, 1, accuracy: 1e-12)
    }

    /// El giro del plano y el giro 3D alrededor de +y que se le da a
    /// RealityKit tienen el signo contrario. Este test lo deja fijado.
    func testElGiroAlrededorDeYLlevaElSignoCambiado() {
        let theta = degrees(30)
        let transform = RigidTransform2D(theta: theta, t: .zero)
        let p = Vec2(x: 3, z: -2)
        let expected = transform.apply(p)

        // Giro a derechas alrededor de +y: x' = x·cos + z·sin, z' = −x·sin + z·cos.
        let yaw = transform.yawAroundY
        let x = p.x * cos(yaw) + p.z * sin(yaw)
        let z = -p.x * sin(yaw) + p.z * cos(yaw)
        XCTAssertEqual(x, expected.x, accuracy: 1e-12)
        XCTAssertEqual(z, expected.z, accuracy: 1e-12)
        XCTAssertEqual(yaw, -theta)
    }

    func testAplicarEInvertir() {
        let transform = RigidTransform2D(theta: degrees(40), t: Vec2(x: 5, z: -7))
        let p = Vec2(x: 12, z: 3)
        let back = transform.inverse(transform.apply(p))
        XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
        XCTAssertEqual(back.z, p.z, accuracy: 1e-9)
    }

    func testComposicion() {
        let first = RigidTransform2D(theta: degrees(20), t: Vec2(x: 1, z: 2))
        let second = RigidTransform2D(theta: degrees(-50), t: Vec2(x: -4, z: 6))
        let both = second.composed(after: first)
        let p = Vec2(x: 7, z: -3)
        let expected = second.apply(first.apply(p))
        let actual = both.apply(p)
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(actual.z, expected.z, accuracy: 1e-9)
    }

    func testEnvolverAngulos() {
        XCTAssertEqual(RigidTransform2D.wrap(degrees(190)), degrees(-170), accuracy: 1e-9)
        XCTAssertEqual(RigidTransform2D.wrap(degrees(-190)), degrees(170), accuracy: 1e-9)
        XCTAssertEqual(RigidTransform2D.wrap(degrees(720 + 10)), degrees(10), accuracy: 1e-9)
    }

    // MARK: - Mínimos cuadrados

    func testSinRuidoRecuperaElAjusteExacto() throws {
        let truth = RigidTransform2D(theta: degrees(-23), t: Vec2(x: 40, z: -15))
        let pairs = walk(samples: 30, leg: 50).map {
            AlignmentPair(geo: $0, ar: truth.apply($0), accuracy: 5)
        }
        let solved = try XCTUnwrap(AlignmentSolver.solve(pairs))
        XCTAssertEqual(solved.theta, truth.theta, accuracy: 1e-9)
        XCTAssertEqual(solved.t.x, truth.t.x, accuracy: 1e-6)
        XCTAssertEqual(solved.t.z, truth.t.z, accuracy: 1e-6)
    }

    func testConGiroFijoSoloCalculaElDesplazamiento() throws {
        let pairs = [
            AlignmentPair(geo: Vec2(x: 0, z: 0), ar: Vec2(x: 10, z: 5), accuracy: 5),
            AlignmentPair(geo: Vec2(x: 4, z: 0), ar: Vec2(x: 14, z: 5), accuracy: 5)
        ]
        let solved = try XCTUnwrap(AlignmentSolver.solve(pairs, fixedTheta: 0))
        XCTAssertEqual(solved.theta, 0)
        XCTAssertEqual(solved.t.x, 10, accuracy: 1e-9)
        XCTAssertEqual(solved.t.z, 5, accuracy: 1e-9)
        XCTAssertNil(AlignmentSolver.solve([]))
    }

    func testLasLecturasPrecisasPesanMas() throws {
        // Una lectura buena y una mala que discrepan en 10 m.
        let pairs = [
            AlignmentPair(geo: .zero, ar: Vec2(x: 0, z: 0), accuracy: 2),
            AlignmentPair(geo: .zero, ar: Vec2(x: 10, z: 0), accuracy: 10)
        ]
        let solved = try XCTUnwrap(AlignmentSolver.solve(pairs, fixedTheta: 0))
        // Pesos 1/4 y 1/100: el resultado queda a 0,38 m de la buena.
        XCTAssertEqual(solved.t.x, 10 * 0.01 / 0.26, accuracy: 1e-9)
    }

    /// Criterio del plan: con 8 m de ruido y 15° de giro, recupera el giro
    /// con 3° de margen y el desplazamiento con 3 m. El ruido es uniforme en
    /// un círculo de 8 m de radio y el desplazamiento se mide donde está el
    /// usuario al final del paseo, que es donde se nota.
    func testRecuperaGiroYDesplazamientoConRuidoDeGPS() throws {
        let truth = RigidTransform2D(theta: degrees(15), t: Vec2(x: 12, z: -7))
        let path = walk(samples: 60, leg: 100)

        var worstAngle = 0.0
        var worstPosition = 0.0
        for seed in 1...25 {
            var random = SeededRandom(seed: UInt64(seed))
            var estimator = AlignmentEstimator()
            for point in path {
                let gps = point + random.inDisc(radius: 8)
                estimator.addGPS(geo: gps, ar: truth.apply(point), accuracy: 8)
            }
            let solved = try XCTUnwrap(estimator.transform)
            XCTAssertTrue(estimator.rotationSolved)

            let angleError = abs(RigidTransform2D.wrap(solved.theta - truth.theta)) * 180 / .pi
            let last = path[path.count - 1]
            let positionError = solved.apply(last).distance(to: truth.apply(last))
            worstAngle = max(worstAngle, angleError)
            worstPosition = max(worstPosition, positionError)
        }
        XCTAssertLessThan(worstAngle, 3, "Peor error de giro en 25 semillas")
        XCTAssertLessThan(worstPosition, 3, "Peor error de posición en 25 semillas")
    }

    // MARK: - Reglas de uso

    func testConMenosDe20MetrosAndadosNoSeEstimaElGiro() throws {
        let truth = RigidTransform2D(theta: degrees(15), t: Vec2(x: 3, z: 4))
        var estimator = AlignmentEstimator()
        for i in 0..<10 {
            let point = Vec2(x: Double(i) * 1.5, z: 0)
            estimator.addGPS(geo: point, ar: truth.apply(point), accuracy: 5)
        }
        XCTAssertFalse(estimator.rotationSolved)
        XCTAssertEqual(try XCTUnwrap(estimator.transform).theta, 0)
        XCTAssertLessThan(estimator.spread, 20)

        for i in 10..<30 {
            let point = Vec2(x: Double(i) * 1.5, z: 0)
            estimator.addGPS(geo: point, ar: truth.apply(point), accuracy: 5)
        }
        XCTAssertTrue(estimator.rotationSolved)
        XCTAssertEqual(try XCTUnwrap(estimator.transform).theta, truth.theta, accuracy: 1e-6)
    }

    func testAlPararseConservaElGiroConocido() throws {
        let truth = RigidTransform2D(theta: degrees(-10), t: .zero)
        var config = AlignmentEstimator.Config()
        config.windowSize = 10
        var estimator = AlignmentEstimator(config: config)
        for i in 0..<30 {
            let point = Vec2(x: Double(i) * 3, z: 0)
            estimator.addGPS(geo: point, ar: truth.apply(point), accuracy: 5)
        }
        XCTAssertTrue(estimator.rotationSolved)
        XCTAssertEqual(estimator.pairs.count, 10)

        // Parado: las lecturas repetidas no empujan la trayectoria fuera de
        // la ventana, así que el giro se conserva.
        let stop = Vec2(x: 87, z: 0)
        for _ in 0..<20 {
            estimator.addGPS(geo: stop, ar: truth.apply(stop), accuracy: 4)
        }
        XCTAssertEqual(estimator.pairs.count, 10)
        XCTAssertEqual(try XCTUnwrap(estimator.transform).theta, truth.theta, accuracy: 1e-6)
    }

    func testDescartaLecturasImprecisas() {
        var estimator = AlignmentEstimator()
        XCTAssertFalse(estimator.addGPS(geo: .zero, ar: .zero, accuracy: 30))
        XCTAssertFalse(estimator.addGPS(geo: .zero, ar: .zero, accuracy: -1))
        XCTAssertNil(estimator.transform)
        XCTAssertTrue(estimator.addGPS(geo: .zero, ar: .zero, accuracy: 15))
        XCTAssertNotNil(estimator.transform)
    }

    func testParadoSeQuedaConLaLecturaMasPrecisa() {
        var estimator = AlignmentEstimator()
        estimator.addGPS(geo: Vec2(x: 5, z: 0), ar: .zero, accuracy: 10)
        XCTAssertFalse(estimator.addGPS(geo: Vec2(x: 9, z: 0), ar: Vec2(x: 0.2, z: 0), accuracy: 12))
        XCTAssertTrue(estimator.addGPS(geo: Vec2(x: 1, z: 0), ar: Vec2(x: 0.3, z: 0), accuracy: 4))
        XCTAssertEqual(estimator.pairs.count, 1)
        XCTAssertEqual(estimator.pairs[0].accuracy, 4)
    }

    func testLaVentanaEsDeslizante() {
        var config = AlignmentEstimator.Config()
        config.windowSize = 30
        var estimator = AlignmentEstimator(config: config)
        for i in 0..<100 {
            estimator.addGPS(geo: Vec2(x: Double(i) * 2, z: 0), ar: Vec2(x: Double(i) * 2, z: 0), accuracy: 5)
        }
        XCTAssertEqual(estimator.pairs.count, 30)
        XCTAssertEqual(estimator.pairs.first?.geo.x, 140)
    }

    // MARK: - Anclaje en boca

    func testElAnclajeColocaLaBocaExactamenteDondeEstaElUsuario() throws {
        var estimator = AlignmentEstimator()
        // GPS con 9 m de sesgo.
        for i in 0..<10 {
            let ar = Vec2(x: Double(i) * 2, z: 0)
            estimator.addGPS(geo: ar + Vec2(x: 9, z: 0), ar: ar, accuracy: 8)
        }
        let boca = Vec2(x: 18, z: 0)
        let userAR = Vec2(x: 18, z: 0)
        estimator.setAnchor(geo: boca, ar: userAR)
        XCTAssertTrue(estimator.hasAnchor)

        let solved = try XCTUnwrap(estimator.transform)
        let mapped = solved.apply(boca)
        XCTAssertEqual(mapped.x, userAR.x, accuracy: 1e-9)
        XCTAssertEqual(mapped.z, userAR.z, accuracy: 1e-9)
    }

    func testTrasElAnclajeElGPSSesgadoApenasMueveElTunel() throws {
        var estimator = AlignmentEstimator()
        estimator.setAnchor(geo: .zero, ar: .zero)
        // Diez metros andados con un GPS que marca 8 m de más al este.
        for i in 1...10 {
            let ar = Vec2(x: 0, z: -Double(i))
            estimator.addGPS(geo: ar + Vec2(x: 8, z: 0), ar: ar, accuracy: 8)
        }
        let solved = try XCTUnwrap(estimator.transform)
        // Sin anclaje el túnel se iría 8 m; con él, bastante menos de 2 m.
        XCTAssertLessThan(solved.apply(.zero).length, 2)
        XCTAssertEqual(estimator.walkedSinceAnchor, 10, accuracy: 1e-6)
    }

    func testReiniciar() {
        var estimator = AlignmentEstimator()
        estimator.setAnchor(geo: .zero, ar: .zero)
        estimator.addGPS(geo: Vec2(x: 3, z: 0), ar: Vec2(x: 3, z: 0), accuracy: 5)
        estimator.reset()
        XCTAssertNil(estimator.transform)
        XCTAssertFalse(estimator.hasAnchor)
        XCTAssertTrue(estimator.pairs.isEmpty)
        XCTAssertEqual(estimator.walkedSinceAnchor, 0)
    }

    // MARK: - Suavizado

    func testElPrimerAjusteSeAplicaDeGolpe() {
        var smoother = AlignmentSmoother()
        let target = RigidTransform2D(theta: 0.2, t: Vec2(x: 30, z: -4))
        XCTAssertEqual(smoother.step(toward: target, userAR: .zero, dt: 0.1), target)
    }

    func testElTunelSeMueveComoMuchoMedioMetroPorSegundo() {
        var smoother = AlignmentSmoother()
        smoother.snap(to: .identity)
        let target = RigidTransform2D(theta: 0, t: Vec2(x: 10, z: 0))
        let user = Vec2(x: 3, z: 2)

        let afterOneSecond = smoother.step(toward: target, userAR: user, dt: 1)
        XCTAssertEqual(afterOneSecond.t.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(afterOneSecond.t.z, 0, accuracy: 1e-9)

        var current = afterOneSecond
        for _ in 0..<19 {
            current = smoother.step(toward: target, userAR: user, dt: 1)
        }
        XCTAssertEqual(current.t.x, 10, accuracy: 1e-9, "Llega en 20 s y no se pasa")
        current = smoother.step(toward: target, userAR: user, dt: 1)
        XCTAssertEqual(current.t.x, 10, accuracy: 1e-9)
    }

    func testElGiroTambienSeLimitaYNoMueveAlUsuario() {
        var smoother = AlignmentSmoother()
        smoother.snap(to: .identity)
        let user = Vec2(x: 80, z: -40)
        // Mismo punto para el usuario, pero girado 30° a su alrededor.
        let theta = degrees(30)
        let target = RigidTransform2D(theta: theta, t: user - RigidTransform2D.rotate(user, by: theta))

        let next = smoother.step(toward: target, userAR: user, dt: 1)
        XCTAssertEqual(next.theta, degrees(3), accuracy: 1e-9)
        // El usuario sigue creyendo estar en el mismo sitio.
        let geoBefore = RigidTransform2D.identity.inverse(user)
        let geoAfter = next.inverse(user)
        XCTAssertEqual(geoAfter.distance(to: geoBefore), 0, accuracy: 1e-9)
    }

    // MARK: - Ajuste manual

    func testArrastrarDesplazaElTunel() {
        var manual = ManualAdjustment()
        XCTAssertTrue(manual.isIdentity)
        manual.translate(by: Vec2(x: 2, z: -1))
        manual.translate(by: Vec2(x: 1, z: 0))
        let automatic = RigidTransform2D(theta: degrees(10), t: Vec2(x: 5, z: 5))
        let final = manual.applied(to: automatic)
        let p = Vec2(x: 20, z: 7)
        let expected = automatic.apply(p) + Vec2(x: 3, z: -1)
        XCTAssertEqual(final.apply(p).x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(final.apply(p).z, expected.z, accuracy: 1e-9)
    }

    func testGirarConDosDedosGiraAlrededorDelUsuario() {
        var manual = ManualAdjustment()
        let pivot = Vec2(x: 4, z: -9)
        manual.rotate(by: degrees(25), around: pivot)
        let final = manual.applied(to: .identity)

        // El punto bajo el usuario no se mueve.
        XCTAssertEqual(final.apply(pivot).x, pivot.x, accuracy: 1e-9)
        XCTAssertEqual(final.apply(pivot).z, pivot.z, accuracy: 1e-9)
        // Un punto a 10 m se desplaza 2·10·sin(12,5°).
        let p = pivot + Vec2(x: 10, z: 0)
        XCTAssertEqual(final.apply(p).distance(to: p), 2 * 10 * sin(degrees(12.5)), accuracy: 1e-9)

        manual.reset()
        XCTAssertTrue(manual.isIdentity)
    }

    // MARK: - Sesiones grabadas

    func testUnaSesionGrabadaSeReproduceIgual() throws {
        let origin = GeoPoint(latitude: 43.2627, longitude: -2.9335)
        let frame = LocalFrame(origin: origin)
        let truth = RigidTransform2D(theta: degrees(12), t: Vec2(x: -6, z: 9))

        var recording = SessionRecording(
            inicio: "2026-11-17T12:00:00Z", dispositivo: "iPhone14,5", modo: "B",
            origenLat: origin.latitude, origenLon: origin.longitude
        )
        for (i, point) in walk(samples: 40, leg: 40).enumerated() {
            let geo = frame.geo(point)
            let ar = truth.apply(point)
            var sample = SessionSample(t: Double(i))
            sample.lat = geo.latitude
            sample.lon = geo.longitude
            sample.accuracy = 6
            sample.arX = ar.x
            sample.arY = 1.4
            sample.arZ = ar.z
            sample.tracking = "normal"
            recording.muestras.append(sample)
        }

        // Pasa por JSON, como el fichero que se comparte desde el iPhone.
        let decoded = try SessionRecording.decode(try recording.encoded())
        XCTAssertEqual(decoded, recording)

        let estimator = SessionReplay.run(decoded)
        let solved = try XCTUnwrap(estimator.transform)
        XCTAssertEqual(solved.theta, truth.theta, accuracy: 1e-6)
        XCTAssertEqual(solved.t.x, truth.t.x, accuracy: 1e-4)
        XCTAssertEqual(solved.t.z, truth.t.z, accuracy: 1e-4)
    }
}
