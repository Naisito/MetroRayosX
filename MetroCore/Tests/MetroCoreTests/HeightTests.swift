import XCTest
@testable import MetroCore

final class HeightTests: XCTestCase {
    /// Ruido repetible, de −1 a 1.
    private struct Noise {
        var state: UInt64

        mutating func next() -> Double {
            state = (state &* 1_664_525 &+ 1_013_904_223) % 4_294_967_296
            return Double(state) / 4_294_967_296 * 2 - 1
        }
    }

    func testEnElSueloNoTocaNada() {
        var noise = Noise(state: 3)
        var estimator = HeightEstimator()
        for _ in 0..<40 {
            estimator.add(altitude: 20 + 1.4 + noise.next() * 2.5, accuracy: 4, ground: 20)
        }
        XCTAssertEqual(estimator.lift, 0)
    }

    func testSobreUnaPasarelaSubeYAlBajarVuelve() {
        var noise = Noise(state: 5)
        var estimator = HeightEstimator()
        for _ in 0..<3 {
            estimator.add(altitude: 20 + 1.4 + 6.5, accuracy: 4, ground: 20)
        }
        XCTAssertEqual(estimator.lift, 0, "con tres lecturas aún no se fía")
        for _ in 0..<20 {
            estimator.add(altitude: 20 + 1.4 + 6.5 + noise.next() * 2, accuracy: 4, ground: 20)
        }
        XCTAssertEqual(estimator.lift, 6.5, accuracy: 1.5)

        for _ in 0..<20 {
            estimator.add(altitude: 20 + 1.4 + noise.next() * 2, accuracy: 4, ground: 20)
        }
        XCTAssertEqual(estimator.lift, 0)
    }

    func testUsaLaAlturaRealDelMovil() {
        // El móvil en alto (1,9 m) sobre una pasarela de 5 m.
        var estimator = HeightEstimator()
        for _ in 0..<10 {
            estimator.add(altitude: 10 + 5 + 1.9, accuracy: 3, ground: 10, phoneHeight: 1.9)
        }
        XCTAssertEqual(estimator.lift, 5, accuracy: 0.01)
    }

    func testIgnoraLecturasQueNoValen() {
        var estimator = HeightEstimator()
        for _ in 0..<20 {
            // Precisión mala, sin dato, y otra referencia de altitudes.
            estimator.add(altitude: 40, accuracy: 25, ground: 20)
            estimator.add(altitude: 40, accuracy: -1, ground: 20)
            estimator.add(altitude: 40, accuracy: 0, ground: 20)
            estimator.add(altitude: .nan, accuracy: 4, ground: 20)
            estimator.add(altitude: 40, accuracy: 4, ground: .nan)
            estimator.add(altitude: 20 + 95, accuracy: 4, ground: 20)
        }
        XCTAssertEqual(estimator.lift, 0)
    }

    func testReinicio() {
        var estimator = HeightEstimator()
        for _ in 0..<10 {
            estimator.add(altitude: 30, accuracy: 3, ground: 20)
        }
        XCTAssertGreaterThan(estimator.lift, 4)
        estimator.reset()
        XCTAssertEqual(estimator.lift, 0)
        XCTAssertEqual(estimator, HeightEstimator())
    }
}
