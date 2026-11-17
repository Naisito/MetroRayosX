import Foundation

// Ajuste GPS <-> AR del Modo B (ver «Matemáticas clave» en PLAN.md).
//
// Todo ocurre en el plano horizontal de la escena: x = este, z = sur.
// `geo` es una posición según el GPS, ya pasada a ese plano con `LocalFrame`.
// `ar` es la posición del móvil según ARKit en el mismo instante.
// Se busca el giro θ y el desplazamiento t con  ar ≈ R(θ)·geo + t.

/// Giro y desplazamiento en el plano (x, z).
public struct RigidTransform2D: Equatable, Sendable {
    /// Giro en radianes. Positivo lleva +x hacia +z.
    public var theta: Double
    public var t: Vec2

    public init(theta: Double, t: Vec2) {
        self.theta = theta
        self.t = t
    }

    public static let identity = RigidTransform2D(theta: 0, t: .zero)

    public static func rotate(_ p: Vec2, by theta: Double) -> Vec2 {
        let c = cos(theta)
        let s = sin(theta)
        return Vec2(x: c * p.x - s * p.z, z: s * p.x + c * p.z)
    }

    /// De plano geográfico a plano AR.
    public func apply(_ p: Vec2) -> Vec2 {
        RigidTransform2D.rotate(p, by: theta) + t
    }

    /// De plano AR a plano geográfico.
    public func inverse(_ p: Vec2) -> Vec2 {
        RigidTransform2D.rotate(p - t, by: -theta)
    }

    /// Transformación equivalente a aplicar primero `other` y después esta.
    public func composed(after other: RigidTransform2D) -> RigidTransform2D {
        RigidTransform2D(
            theta: theta + other.theta,
            t: RigidTransform2D.rotate(other.t, by: theta) + t
        )
    }

    /// Ángulo del giro equivalente alrededor del eje +y (arriba) en un sistema
    /// a derechas como el de ARKit y RealityKit. Lleva el signo cambiado:
    /// girar +x hacia +z es un giro negativo alrededor de +y.
    public var yawAroundY: Double {
        -theta
    }

    /// Lleva un ángulo al intervalo (−π, π].
    public static func wrap(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi {
            a -= 2 * .pi
        } else if a <= -.pi {
            a += 2 * .pi
        }
        return a
    }
}

/// Una lectura de GPS emparejada con la posición AR del mismo instante.
public struct AlignmentPair: Equatable, Sendable {
    public let geo: Vec2
    public let ar: Vec2
    /// Precisión horizontal en metros (1 sigma aproximado).
    public let accuracy: Double

    public init(geo: Vec2, ar: Vec2, accuracy: Double) {
        self.geo = geo
        self.ar = ar
        self.accuracy = accuracy
    }

    public var weight: Double {
        let a = max(accuracy, 0.25)
        return 1 / (a * a)
    }
}

public enum AlignmentSolver {
    /// Mínimos cuadrados ponderados con solución directa.
    /// Con `fixedTheta` solo se calcula el desplazamiento.
    public static func solve(_ pairs: [AlignmentPair], fixedTheta: Double? = nil) -> RigidTransform2D? {
        guard !pairs.isEmpty else {
            return nil
        }
        var totalWeight = 0.0
        var geoMean = Vec2.zero
        var arMean = Vec2.zero
        for pair in pairs {
            let w = pair.weight
            totalWeight += w
            geoMean = geoMean + pair.geo * w
            arMean = arMean + pair.ar * w
        }
        guard totalWeight > 0 else {
            return nil
        }
        geoMean = geoMean * (1 / totalWeight)
        arMean = arMean * (1 / totalWeight)

        var theta = fixedTheta ?? 0
        if fixedTheta == nil {
            var crossSum = 0.0
            var dotSum = 0.0
            for pair in pairs {
                let g = pair.geo - geoMean
                let a = pair.ar - arMean
                crossSum += pair.weight * g.cross(a)
                dotSum += pair.weight * g.dot(a)
            }
            if abs(crossSum) > 1e-12 || abs(dotSum) > 1e-12 {
                theta = atan2(crossSum, dotSum)
            }
        }
        let t = arMean - RigidTransform2D.rotate(geoMean, by: theta)
        return RigidTransform2D(theta: theta, t: t)
    }
}

/// Estado del ajuste: ventana deslizante de parejas, anclaje en boca y reglas de uso.
public struct AlignmentEstimator: Sendable {
    public struct Config: Sendable {
        /// Parejas que se conservan.
        public var windowSize = 60
        /// Metros que hay que haber andado para estimar el giro.
        public var minWalkForRotation = 20.0
        /// Parejas mínimas para estimar el giro.
        public var minPairsForRotation = 6
        /// Lecturas de GPS peores que esto se descartan.
        public var maxGPSAccuracy = 15.0
        /// Separación mínima entre parejas consecutivas, en metros de AR.
        public var minStep = 1.0
        /// Precisión que se le da al anclaje en una boca.
        public var anchorAccuracy = 0.75
        /// El anclaje pierde confianza con lo andado: deriva de ARKit por metro.
        public var anchorDriftPerMeter = 0.03

        public init() {}
    }

    public var config: Config
    public private(set) var pairs: [AlignmentPair] = []
    public private(set) var transform: RigidTransform2D?
    /// Último giro conocido. Empieza en 0: se confía en la brújula.
    public private(set) var theta = 0.0
    /// `true` cuando el giro sale de la trayectoria y no de la brújula.
    public private(set) var rotationSolved = false

    private var anchor: AlignmentPair?
    private var pathAtAnchor = 0.0
    private var pathLength = 0.0
    private var lastTracked: Vec2?

    public init(config: Config = Config()) {
        self.config = config
    }

    public var hasAnchor: Bool {
        anchor != nil
    }

    /// Metros andados desde el anclaje en boca (0 si no hay anclaje).
    public var walkedSinceAnchor: Double {
        anchor == nil ? 0 : pathLength - pathAtAnchor
    }

    /// Extensión de la trayectoria AR guardada en la ventana.
    public var spread: Double {
        guard let first = pairs.first else {
            return 0
        }
        var minX = first.ar.x
        var maxX = first.ar.x
        var minZ = first.ar.z
        var maxZ = first.ar.z
        for pair in pairs {
            minX = min(minX, pair.ar.x)
            maxX = max(maxX, pair.ar.x)
            minZ = min(minZ, pair.ar.z)
            maxZ = max(maxZ, pair.ar.z)
        }
        return Vec2(x: maxX - minX, z: maxZ - minZ).length
    }

    /// Acumula lo andado según ARKit. Se llama con cada posición del móvil.
    public mutating func track(ar: Vec2) {
        if let last = lastTracked {
            let step = last.distance(to: ar)
            // Los saltos grandes son relocalizaciones de ARKit, no pasos.
            if step < 5 {
                pathLength += step
            }
        }
        lastTracked = ar
    }

    /// Añade una lectura de GPS. Devuelve `false` si se descarta.
    @discardableResult
    public mutating func addGPS(geo: Vec2, ar: Vec2, accuracy: Double) -> Bool {
        guard accuracy >= 0, accuracy <= config.maxGPSAccuracy else {
            return false
        }
        track(ar: ar)
        let pair = AlignmentPair(geo: geo, ar: ar, accuracy: accuracy)
        if let last = pairs.last, last.ar.distance(to: ar) < config.minStep {
            // Parado en el sitio: se queda la lectura más precisa.
            if accuracy <= last.accuracy {
                pairs[pairs.count - 1] = pair
            } else {
                return false
            }
        } else {
            pairs.append(pair)
            if pairs.count > config.windowSize {
                pairs.removeFirst(pairs.count - config.windowSize)
            }
        }
        solve()
        return true
    }

    /// «Estoy en esta boca»: la posición AR actual corresponde a esa coordenada.
    public mutating func setAnchor(geo: Vec2, ar: Vec2) {
        track(ar: ar)
        anchor = AlignmentPair(geo: geo, ar: ar, accuracy: config.anchorAccuracy)
        pathAtAnchor = pathLength
        // Las lecturas anteriores llevan el sesgo del GPS que el anclaje corrige.
        pairs.removeAll()
        solve()
    }

    public mutating func reset() {
        pairs.removeAll()
        anchor = nil
        transform = nil
        theta = 0
        rotationSolved = false
        pathLength = 0
        pathAtAnchor = 0
        lastTracked = nil
    }

    private mutating func solve() {
        var all = pairs
        if let anchor = anchor {
            let accuracy = config.anchorAccuracy + config.anchorDriftPerMeter * (pathLength - pathAtAnchor)
            all.append(AlignmentPair(geo: anchor.geo, ar: anchor.ar, accuracy: accuracy))
        }
        guard !all.isEmpty else {
            transform = nil
            return
        }

        let canRotate = pairs.count >= config.minPairsForRotation && spread >= config.minWalkForRotation
        if canRotate, let solved = AlignmentSolver.solve(all) {
            theta = solved.theta
            rotationSolved = true
            transform = solved
        } else {
            transform = AlignmentSolver.solve(all, fixedTheta: theta)
        }
    }
}

/// Aplica el ajuste poco a poco para que el túnel no dé saltos.
public struct AlignmentSmoother: Sendable {
    /// Metros por segundo, medidos en la posición del usuario.
    public var maxSpeed = 0.5
    /// Radianes por segundo.
    public var maxTurnRate = 3.0 * .pi / 180

    public private(set) var current: RigidTransform2D?

    public init() {}

    /// Salta directamente a `target` (primer ajuste, anclaje en boca, reinicio).
    public mutating func snap(to target: RigidTransform2D?) {
        current = target
    }

    /// Avanza `dt` segundos hacia `target`. `userAR` es la posición AR del
    /// móvil: el límite de velocidad se mide ahí, que es donde se nota.
    @discardableResult
    public mutating func step(toward target: RigidTransform2D, userAR: Vec2, dt: Double) -> RigidTransform2D {
        guard let current = current else {
            self.current = target
            return target
        }
        let dt = max(dt, 0)

        let turn = RigidTransform2D.wrap(target.theta - current.theta)
        let maxTurn = maxTurnRate * dt
        let theta = current.theta + min(max(turn, -maxTurn), maxTurn)

        // Dónde cree cada transformación que está el usuario.
        let geoNow = current.inverse(userAR)
        let geoTarget = target.inverse(userAR)
        var move = geoTarget - geoNow
        let maxMove = maxSpeed * dt
        if move.length > maxMove {
            move = move.normalized * maxMove
        }
        let geoNext = geoNow + move
        let next = RigidTransform2D(
            theta: theta,
            t: userAR - RigidTransform2D.rotate(geoNext, by: theta)
        )
        self.current = next
        return next
    }
}

/// Corrección manual, guardada como un desplazamiento extra encima del ajuste
/// automático. Vive en el plano AR.
public struct ManualAdjustment: Equatable, Sendable {
    public private(set) var transform = RigidTransform2D.identity

    public init() {}

    public var isIdentity: Bool {
        transform == .identity
    }

    /// Un dedo: desplaza el túnel.
    public mutating func translate(by delta: Vec2) {
        transform.t = transform.t + delta
    }

    /// Dos dedos: gira el túnel alrededor de `pivot` (la posición del usuario).
    public mutating func rotate(by angle: Double, around pivot: Vec2) {
        transform = RigidTransform2D(
            theta: transform.theta + angle,
            t: RigidTransform2D.rotate(transform.t - pivot, by: angle) + pivot
        )
    }

    public mutating func reset() {
        transform = .identity
    }

    /// Ajuste final: el automático y, encima, el manual.
    public func applied(to automatic: RigidTransform2D) -> RigidTransform2D {
        transform.composed(after: automatic)
    }
}
