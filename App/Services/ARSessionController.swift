import ARKit
import Combine
import CoreLocation
import Foundation
import simd

/// Configura y vigila la sesión de ARKit.
///
/// Modo A (geotracking): `ARGeoTrackingConfiguration` con un `ARGeoAnchor`
/// como origen de la escena. Solo donde Apple tiene cobertura.
/// Modo B (manual): `ARWorldTrackingConfiguration` orientada con la brújula;
/// la posición la pone el ajuste GPS-AR de MetroCore.
final class ARSessionController: NSObject, ObservableObject {
    enum Mode: String {
        case geo = "A"
        case manual = "B"
    }

    /// Segundos que se espera a que el geotracking se localice antes de pasar al Modo B.
    static let geoTimeout: TimeInterval = 30

    @Published private(set) var mode: Mode = .manual
    @Published private(set) var isRunning = false
    @Published private(set) var trackingText = "sin iniciar"
    /// `true` mientras ARKit no sigue bien el movimiento.
    @Published private(set) var trackingLimited = true
    @Published private(set) var geoText = ""
    @Published private(set) var errorText: String?

    /// Se llama con cada imagen de la cámara, en el hilo principal.
    var onFrame: ((ARFrame) -> Void)?
    /// Se llama cuando el Modo A se abandona y la sesión pasa al Modo B.
    var onFallbackToManual: (() -> Void)?

    private weak var session: ARSession?
    private var planes: [UUID: ARPlaneAnchor] = [:]
    private var geoAnchor: ARGeoAnchor?
    private var geoLocalized = false
    private var geoStart: Date?
    private var smoothedGround: Float?
    /// Identifica la comprobación de cobertura en curso, para ignorar respuestas tardías.
    private var pendingCheck: UUID?

    func attach(to session: ARSession) {
        self.session = session
        session.delegate = self
    }

    // MARK: - Arranque y parada

    /// Arranca la sesión. Si hay cobertura de geotracking en `coordinate`
    /// usa el Modo A; si no, el Modo B.
    func start(at coordinate: CLLocationCoordinate2D?) {
        guard !isRunning else {
            return
        }
        errorText = nil
        guard ARWorldTrackingConfiguration.isSupported else {
            errorText = "Este dispositivo no es compatible con ARKit."
            return
        }
        isRunning = true
        guard ARGeoTrackingConfiguration.isSupported else {
            runManual(reset: true)
            return
        }

        trackingText = "comprobando geotracking"
        let check = UUID()
        pendingCheck = check
        let completion: (Bool, Error?) -> Void = { [weak self] available, error in
            let detail = error?.localizedDescription
            DispatchQueue.main.async {
                guard let self = self, self.pendingCheck == check, self.isRunning else {
                    return
                }
                self.pendingCheck = nil
                var message = "Geotracking en la posición actual: " + (available ? "disponible" : "no disponible")
                if let detail = detail {
                    message += " (" + detail + ")"
                }
                AppLog.shared.write(message, category: "ar")
                if available {
                    self.runGeo()
                } else {
                    self.runManual(reset: true)
                }
            }
        }
        if let coordinate = coordinate {
            ARGeoTrackingConfiguration.checkAvailability(at: coordinate, completionHandler: completion)
        } else {
            // Sin lectura de GPS todavía: ARKit pregunta por la posición actual.
            ARGeoTrackingConfiguration.checkAvailability(completionHandler: completion)
        }
        // Sin conexión la respuesta puede tardar: no se espera más de 4 s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, self.pendingCheck == check, self.isRunning else {
                return
            }
            self.pendingCheck = nil
            AppLog.shared.write("Geotracking: sin respuesta, se usa el Modo B", category: "ar")
            self.runManual(reset: true)
        }
    }

    func pause() {
        guard isRunning else {
            return
        }
        isRunning = false
        pendingCheck = nil
        session?.pause()
        trackingText = "en pausa"
        trackingLimited = true
        AppLog.shared.write("Sesión AR en pausa", category: "ar")
    }

    /// Modo B: mundo alineado con la gravedad y el norte de la brújula.
    func runManual(reset: Bool) {
        guard let session = session else {
            return
        }
        let wasGeo = mode == .geo
        mode = .manual
        geoAnchor = nil
        geoLocalized = false
        geoStart = nil
        geoText = ""

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .none
        var options: ARSession.RunOptions = []
        if reset {
            options = [.resetTracking, .removeExistingAnchors]
            planes.removeAll()
            smoothedGround = nil
        }
        session.run(configuration, options: options)
        AppLog.shared.write("Sesión AR en Modo B (manual)\(reset ? ", seguimiento reiniciado" : "")", category: "ar")
        if wasGeo {
            onFallbackToManual?()
        }
    }

    /// Modo A: geotracking de Apple.
    private func runGeo() {
        guard let session = session else {
            return
        }
        mode = .geo
        geoAnchor = nil
        geoLocalized = false
        geoStart = Date()
        geoText = "iniciando"
        planes.removeAll()
        smoothedGround = nil

        let configuration = ARGeoTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .none
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        AppLog.shared.write("Sesión AR en Modo A (geotracking)", category: "ar")
    }

    // MARK: - Modo A: ancla geográfica

    /// Coloca (o recoloca) el ancla geográfica que hace de origen de la escena.
    func setGeoOrigin(_ coordinate: CLLocationCoordinate2D) {
        guard mode == .geo, let session = session else {
            return
        }
        if let old = geoAnchor {
            session.remove(anchor: old)
        }
        let anchor = ARGeoAnchor(coordinate: coordinate)
        geoAnchor = anchor
        session.add(anchor: anchor)
    }

    var hasGeoAnchor: Bool {
        geoAnchor != nil
    }

    /// Transformación del ancla geográfica en el mundo de ARKit, solo cuando
    /// el geotracking está localizado y el ancla se está siguiendo.
    /// Sus ejes son x = este, y = arriba, z = sur: los de la escena.
    var geoOriginTransform: simd_float4x4? {
        guard mode == .geo, geoLocalized, let anchor = geoAnchor, anchor.isTracked else {
            return nil
        }
        return anchor.transform
    }

    /// `true` si el Modo A lleva demasiado tiempo sin localizarse.
    private var geoTimedOut: Bool {
        guard mode == .geo, !geoLocalized, let start = geoStart else {
            return false
        }
        return Date().timeIntervalSince(start) > ARSessionController.geoTimeout
    }

    // MARK: - Suelo

    /// Altura del suelo bajo la cámara en el mundo de ARKit: el plano
    /// horizontal más bajo de los que hay cerca y a una altura razonable
    /// para alguien de pie; si no hay ninguno, 1,4 m por debajo del móvil.
    func groundHeight(camera: simd_float4x4, dt: Float) -> Float {
        let cameraPosition = camera.columns.3
        var lowest: Float?
        for plane in planes.values {
            let center = plane.transform * simd_float4(plane.center.x, plane.center.y, plane.center.z, 1)
            let dx = center.x - cameraPosition.x
            let dz = center.z - cameraPosition.z
            let below = cameraPosition.y - center.y
            guard (dx * dx + dz * dz).squareRoot() < 5, below > 0.7, below < 2.2 else {
                continue
            }
            if lowest == nil || center.y < lowest! {
                lowest = center.y
            }
        }
        let target = lowest ?? (cameraPosition.y - 1.4)
        guard let current = smoothedGround, abs(current - target) < 3 else {
            smoothedGround = target
            return target
        }
        // Se acerca al objetivo sin saltos.
        let next = current + (target - current) * min(dt * 2, 1)
        smoothedGround = next
        return next
    }

    var planeCount: Int {
        planes.count
    }

    var hasDetectedGround: Bool {
        !planes.isEmpty
    }

    private func describe(_ state: ARCamera.TrackingState) -> (text: String, limited: Bool) {
        switch state {
        case .normal:
            return ("normal", false)
        case .notAvailable:
            return ("no disponible", true)
        case .limited(let reason):
            switch reason {
            case .initializing:
                return ("limitado: iniciando", true)
            case .excessiveMotion:
                return ("limitado: demasiado movimiento", true)
            case .insufficientFeatures:
                return ("limitado: poco detalle", true)
            case .relocalizing:
                return ("limitado: relocalizando", true)
            @unknown default:
                return ("limitado", true)
            }
        }
    }
}

extension ARSessionController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if geoTimedOut {
            AppLog.shared.write("Geotracking sin localizar tras 30 s: se pasa al Modo B", category: "ar")
            runManual(reset: true)
            return
        }
        onFrame?(frame)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let description = describe(camera.trackingState)
        if description.text != trackingText {
            AppLog.shared.write("Seguimiento AR: \(description.text)", category: "ar")
        }
        trackingText = description.text
        trackingLimited = description.limited
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal {
                if planes.isEmpty {
                    AppLog.shared.write("Primer plano del suelo detectado", category: "ar")
                }
                planes[plane.identifier] = plane
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal {
                planes[plane.identifier] = plane
            } else if let geo = anchor as? ARGeoAnchor, geo.identifier == geoAnchor?.identifier {
                geoAnchor = geo
            }
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            planes.removeValue(forKey: anchor.identifier)
        }
    }

    func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
        let text: String
        switch geoTrackingStatus.state {
        case .notAvailable:
            text = "no disponible"
        case .initializing:
            text = "iniciando"
        case .localizing:
            text = "localizando: apunta a los edificios"
        case .localized:
            text = "localizado"
        @unknown default:
            text = "desconocido"
        }
        let localized = geoTrackingStatus.state == .localized
        if text != geoText {
            AppLog.shared.write(
                "Geotracking: \(text), precisión \(geoTrackingStatus.accuracy.rawValue), motivo \(geoTrackingStatus.stateReason.rawValue)",
                category: "ar"
            )
        }
        geoText = text
        geoLocalized = localized
        if localized {
            // Una vez localizado ya no se abandona por tiempo.
            geoStart = nil
        } else if mode == .geo, geoStart == nil {
            geoStart = Date()
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        let nsError = error as NSError
        AppLog.shared.write("La sesión AR ha fallado: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)", category: "ar")
        if nsError.domain == ARError.errorDomain, nsError.code == ARError.Code.cameraUnauthorized.rawValue {
            errorText = "Sin permiso de cámara. Actívalo en Ajustes > Privacidad y seguridad > Cámara."
        } else if mode == .geo {
            // El geotracking puede fallar por falta de conexión o de cobertura.
            runManual(reset: true)
            return
        } else {
            errorText = "ARKit ha fallado: \(nsError.localizedDescription)"
        }
        isRunning = false
        trackingLimited = true
    }

    func sessionWasInterrupted(_ session: ARSession) {
        AppLog.shared.write("Sesión AR interrumpida", category: "ar")
        trackingText = "interrumpido"
        trackingLimited = true
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        AppLog.shared.write("Sesión AR reanudada", category: "ar")
    }
}
