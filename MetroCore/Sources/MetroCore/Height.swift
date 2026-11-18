import Foundation

/// Cuánto por encima del terreno está el suelo que pisas (una pasarela, un
/// viaducto, un piso), a partir de la altitud del GPS.
///
/// El relieve es el del terreno desnudo y ARKit solo ve el suelo que tienes
/// debajo: sin esto, desde un puente sobre la vía el túnel se dibuja a la
/// altura de tus pies. Solo actúa cuando la diferencia es clara; por debajo
/// manda el relieve, que es más fino que la altitud del GPS.
public struct HeightEstimator: Equatable, Sendable {
    /// Diferencia a partir de la que se da por bueno que no pisas el terreno.
    public static let engage = 4.0
    /// Por debajo de esta se vuelve al terreno.
    public static let release = 2.5
    /// Lecturas con peor precisión vertical que esta no cuentan.
    public static let worstAccuracy = 10.0
    /// Más que esto es otra referencia de altitudes, no un puente.
    public static let limit = 60.0
    /// Altura a la que se lleva el móvil si no se sabe otra cosa.
    public static let phoneHeight = 1.4

    /// Metros sobre el terreno; 0 mientras no haya una diferencia clara.
    public private(set) var lift = 0.0
    private var samples: [Double] = []

    public init() {}

    public mutating func reset() {
        samples = []
        lift = 0
    }

    /// Añade una lectura. `altitude` y `ground` en metros sobre el nivel del
    /// mar, `accuracy` la precisión vertical (no positiva si no vale) y
    /// `phoneHeight` la altura del móvil sobre el suelo que pisas.
    @discardableResult
    public mutating func add(
        altitude: Double,
        accuracy: Double,
        ground: Double,
        phoneHeight: Double = HeightEstimator.phoneHeight
    ) -> Double {
        guard altitude.isFinite, ground.isFinite, phoneHeight.isFinite else {
            return lift
        }
        guard accuracy.isFinite, accuracy > 0, accuracy <= HeightEstimator.worstAccuracy else {
            return lift
        }
        let delta = altitude - phoneHeight - ground
        guard abs(delta) <= HeightEstimator.limit else {
            return lift
        }
        samples.append(delta)
        if samples.count > 15 {
            samples.removeFirst()
        }
        guard samples.count >= 4 else {
            return lift
        }
        let median = samples.sorted()[samples.count / 2]
        if lift == 0 {
            if median >= HeightEstimator.engage {
                lift = median
            }
        } else if median < HeightEstimator.release {
            lift = 0
        } else {
            lift += (median - lift) * 0.3
        }
        return lift
    }
}
