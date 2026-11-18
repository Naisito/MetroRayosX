import ARKit
import Combine
import CoreLocation
import MetroCore
import RealityKit
import simd
import UIKit

/// Lo que enseña el panel de depuración.
struct HUDState: Equatable {
    var mode = "B"
    var tracking = "sin iniciar"
    var geo = ""
    var gpsAccuracy: Double?
    var heading: Double?
    var headingAccuracy: Double?
    var fps = 0.0
    var entities = 0
    var pendingChunks = 0
    var trains = 0
    var planes = 0
    var pairs = 0
    var spread = 0.0
    var thetaDegrees = 0.0
    var rotationFromPath = false
    var anchored = false
    var manual = false
    var cameraHeight = 0.0
    var lift = 0.0
    var liftManual = false
    var altitude: Double?
    var altitudeAccuracy: Double?
    var latitude: Double?
    var longitude: Double?
}

/// Lo que enseña el panel inferior de la pantalla AR.
struct ARSummary: Equatable {
    var estacion: String?
    var distanciaEstacion: Double?
    var distanciaVia: Double?
    var profundidad: Double?
    var profundidadEstimada = false
    /// Metros a los que estás sobre el terreno (un puente, una pasarela).
    var altura = 0.0
    var alturaManual = false
}

/// Une la sesión de ARKit, el ajuste GPS-AR y la escena.
///
/// Sistemas de coordenadas:
/// - Escena (G): metros alrededor del origen geográfico de la sesión,
///   x = este, y = arriba, z = sur. Ahí se construye todo el contenido.
/// - Mundo de ARKit (W): donde está la cámara.
/// La transformación G -> W es un giro alrededor de la vertical más un
/// desplazamiento. En el Modo A la da el ancla geográfica de Apple; en el
/// Modo B, el ajuste por mínimos cuadrados de MetroCore. Encima va siempre la
/// corrección manual.
@MainActor
final class ARExperience: NSObject, ObservableObject {
    @Published private(set) var labels: [SceneLabel] = []
    @Published private(set) var hud = HUDState()
    @Published private(set) var summary = ARSummary()
    @Published private(set) var advisories: [Advisory] = []
    /// Mensaje a pantalla completa mientras no se puede dibujar nada.
    @Published private(set) var blockingMessage: String? = "Preparando…"
    @Published private(set) var nearbyBocas: [BocaCercana] = []
    @Published private(set) var anchoredAt: String?

    let arView: ARView
    let controller = ARSessionController()
    let recorder = SessionRecorder()

    private let builder = SceneBuilder()
    private let anchorEntity = AnchorEntity(world: SIMD3<Float>(0, 0, 0))

    private var model: MetroModel?
    private var locator: TrainLocator?
    private weak var location: LocationService?
    private weak var realtime: RealtimeService?
    private var cancellables = Set<AnyCancellable>()
    private var active = false
    private var usesRealtime = false

    // Ajuste
    private var sceneFrame: SceneFrame?
    private var estimator = AlignmentEstimator()
    private var smoother = AlignmentSmoother()
    private var manual = ManualAdjustment()
    /// Colocación provisional con la primera lectura de GPS, hasta que el
    /// ajuste tenga parejas buenas.
    private var bootstrap: RigidTransform2D?
    private var bootstrapAccuracy = Double.greatestFiniteMagnitude
    private var applied: RigidTransform2D?
    private var appliedHeight: Float?

    // Altura sobre el terreno: en un puente o una pasarela, el suelo que ve
    // ARKit no es el del relieve. La da la altitud del GPS o se fija a mano.
    private var heightEstimator = HeightEstimator()
    private var manualLift: Double?
    private var appliedLift = 0.0
    private var loggedLift = 0.0

    // Estado por imagen
    private var cameraTransform: simd_float4x4?
    private var cameraPlane: Vec2?
    private var userGeo: GeoPoint?
    private var userGround: Double?
    private var nearestTrack: NearestTrack?
    private var lastRefreshCenter: GeoPoint?
    private var lastFrameTime: TimeInterval = 0
    private var lastSlowUpdate: TimeInterval = 0
    private var lastLabelUpdate: TimeInterval = 0
    private var lastTrainUpdate: TimeInterval = 0
    private var lastRecorderSample: TimeInterval = 0
    private var fps = 0.0
    private var lastPanPoint: SIMD3<Float>?
    private var loggedFirstPlacement = false

    override init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        super.init()

        arView.renderOptions = [
            .disableMotionBlur,
            .disableDepthOfField,
            .disablePersonOcclusion,
            .disableGroundingShadows,
            .disableCameraGrain,
            .disableAREnvironmentLighting
        ]
        arView.scene.addAnchor(anchorEntity)
        anchorEntity.addChild(builder.root)
        builder.root.isEnabled = false

        controller.attach(to: arView.session)
        controller.onFrame = { [weak self] frame in
            self?.update(frame: frame)
        }
        controller.onFallbackToManual = { [weak self] in
            self?.resetAlignment(keepOrigin: true)
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        arView.addGestureRecognizer(pan)
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        arView.addGestureRecognizer(rotation)
    }

    // MARK: - Ciclo de vida

    func configure(model: MetroModel?, location: LocationService, realtime: RealtimeService) {
        if let model = model, self.model == nil {
            self.model = model
            locator = TrainLocator(model: model)
        }
        if self.location == nil {
            self.location = location
            location.$location
                .compactMap { $0 }
                .sink { [weak self] fix in
                    self?.handle(location: fix)
                }
                .store(in: &cancellables)
        }
        self.realtime = realtime
    }

    func start(showTrains: Bool) {
        guard !active else {
            return
        }
        active = true
        UIApplication.shared.isIdleTimerDisabled = true
        location?.start()
        controller.start(at: location?.location?.coordinate)
        setTrains(enabled: showTrains)
        AppLog.shared.write("Pantalla AR abierta", category: "ar")
    }

    func stop() {
        guard active else {
            return
        }
        active = false
        UIApplication.shared.isIdleTimerDisabled = false
        if recorder.isRecording {
            recorder.finish()
        }
        controller.pause()
        setTrains(enabled: false)
        // Al volver, ARKit empieza de cero: el ajuste anterior ya no vale.
        resetAlignment(keepOrigin: false)
        AppLog.shared.write("Pantalla AR cerrada", category: "ar")
    }

    func setTrains(enabled: Bool) {
        guard enabled != usesRealtime else {
            return
        }
        usesRealtime = enabled
        if enabled {
            realtime?.retain()
        } else {
            realtime?.release()
            builder.clearTrains()
        }
    }

    // MARK: - GPS

    private func handle(location fix: CLLocation) {
        guard active, model != nil else {
            return
        }
        // Al abrir la pantalla puede llegar una lectura guardada de hace rato,
        // tomada en otro sitio: no sirve para emparejarla con la pose actual.
        guard abs(fix.timestamp.timeIntervalSinceNow) < 15 else {
            return
        }
        let accuracy = fix.horizontalAccuracy
        let geo = GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)

        if sceneFrame == nil {
            // El origen de la escena se fija con la primera lectura aceptable.
            guard accuracy >= 0, accuracy <= 65 else {
                return
            }
            setOrigin(geo)
        }
        guard let frame = sceneFrame, let camera = cameraPlane else {
            return
        }

        if controller.mode == .manual, !controller.trackingLimited {
            let plane = frame.plane(geo)
            estimator.addGPS(geo: plane, ar: camera, accuracy: accuracy)
            if estimator.transform == nil, accuracy >= 0, accuracy <= bootstrapAccuracy + 5 {
                // Aún sin parejas buenas: se coloca con la lectura más reciente
                // que no sea claramente peor que la mejor vista, para ver algo.
                bootstrap = RigidTransform2D(theta: 0, t: camera - plane)
                bootstrapAccuracy = min(bootstrapAccuracy, accuracy)
            }
        }

        addAltitude(fix, at: geo)

        if recorder.isRecording {
            recorder.add { sample in
                sample.lat = geo.latitude
                sample.lon = geo.longitude
                sample.accuracy = accuracy
                self.fillPose(&sample)
            }
        }
    }

    /// Compara la altitud del GPS con el relieve para saber si pisas el
    /// terreno o algo que está por encima.
    private func addAltitude(_ fix: CLLocation, at geo: GeoPoint) {
        guard let model = model, let camera = cameraTransform, !controller.trackingLimited else {
            return
        }
        // El relieve bajo la posición ya ajustada, que es el que usa la escena.
        guard let ground = userGround ?? model.groundElevation(at: geo) else {
            return
        }
        let floor = controller.groundHeight(camera: camera, dt: 0)
        let phone = min(max(Double(camera.columns.3.y - floor), 0.3), 2.2)
        let before = heightEstimator.lift
        let lift = heightEstimator.add(
            altitude: fix.altitude,
            accuracy: fix.verticalAccuracy,
            ground: ground,
            phoneHeight: phone
        )
        if (before == 0) != (lift == 0) || abs(lift - loggedLift) >= 2 {
            loggedLift = lift
            AppLog.shared.write(
                String(format: "Altura sobre el terreno según el GPS: %.1f m (altitud %.1f ±%.1f, relieve %.1f, móvil a %.1f)",
                       lift, fix.altitude, fix.verticalAccuracy, ground, phone),
                category: "ar"
            )
        }
    }

    /// Botones de altura del panel de calibración: sube o baja a mano los
    /// metros a los que estás sobre el terreno.
    func adjustLift(by delta: Double) {
        let current = manualLift ?? heightEstimator.lift
        let next = min(max((current + delta).rounded(), -10), 80)
        manualLift = next
        lastSlowUpdate = 0
        AppLog.shared.write(String(format: "Altura sobre el terreno a mano: %.0f m", next), category: "ar")
    }

    /// Vuelve a la altura que dé el GPS.
    func resetLift() {
        guard manualLift != nil else {
            return
        }
        manualLift = nil
        lastSlowUpdate = 0
        AppLog.shared.write("Altura sobre el terreno: automática", category: "ar")
    }

    private var targetLift: Double {
        manualLift ?? heightEstimator.lift
    }

    private func setOrigin(_ origin: GeoPoint) {
        guard let model = model else {
            return
        }
        let ground = model.groundElevation(at: origin) ?? 0
        let frame = SceneFrame(origin: origin, cotaRef: ground)
        sceneFrame = frame
        builder.reset(frame: frame)
        lastRefreshCenter = nil
        appliedHeight = nil
        if controller.mode == .geo {
            controller.setGeoOrigin(CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude))
        }
        AppLog.shared.write(
            String(format: "Origen de la escena: %.6f, %.6f, suelo a %.1f m", origin.latitude, origin.longitude, ground),
            category: "ar"
        )
    }

    // MARK: - Calibración

    /// «Estoy en esta boca»: la posición actual del móvil pasa a ser la de la boca.
    func anchor(at boca: BocaCercana) {
        guard let camera = cameraPlane else {
            return
        }
        if sceneFrame == nil {
            setOrigin(boca.boca.geo)
        }
        guard let frame = sceneFrame else {
            return
        }
        let plane = frame.plane(boca.boca.geo)
        manual.reset()

        if controller.mode == .manual {
            estimator.setAnchor(geo: plane, ar: camera)
            smoother.snap(to: estimator.transform)
            applied = estimator.transform
        } else if let automatic = applied {
            // En el Modo A el ancla de Apple sigue mandando; la boca corrige
            // el desplazamiento que quede.
            manual.translate(by: camera - automatic.apply(plane))
        }
        let name = boca.boca.nombre.isEmpty ? boca.estacion.nombre : "\(boca.estacion.nombre) (\(boca.boca.nombre))"
        anchoredAt = name
        lastSlowUpdate = 0
        AppLog.shared.write(
            String(format: "Anclado en la boca %@ (%.6f, %.6f), estaba a %.0f m según la app",
                   name, boca.boca.lat, boca.boca.lon, boca.distance),
            category: "ar"
        )
    }

    /// Botón de reinicio: olvida el ajuste, el anclaje y la corrección manual.
    func restart() {
        AppLog.shared.write("Reinicio de la alineación", category: "ar")
        resetAlignment(keepOrigin: false)
        if controller.mode == .manual, controller.isRunning {
            controller.runManual(reset: true)
        }
        // La siguiente lectura de GPS (una por segundo) vuelve a fijar el origen.
    }

    private func resetAlignment(keepOrigin: Bool) {
        estimator.reset()
        smoother.snap(to: nil)
        manual.reset()
        bootstrap = nil
        bootstrapAccuracy = .greatestFiniteMagnitude
        applied = nil
        appliedHeight = nil
        heightEstimator.reset()
        manualLift = nil
        appliedLift = 0
        loggedLift = 0
        anchoredAt = nil
        loggedFirstPlacement = false
        lastRefreshCenter = nil
        // Tras reiniciar ARKit las posiciones anteriores de la cámara no valen.
        cameraPlane = nil
        cameraTransform = nil
        lastPanPoint = nil
        if !keepOrigin {
            sceneFrame = nil
            builder.reset(frame: nil)
        }
        builder.root.isEnabled = false
        labels = []
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard applied != nil, let ground = groundPoint(at: gesture.location(in: arView)) else {
            lastPanPoint = nil
            return
        }
        switch gesture.state {
        case .began:
            lastPanPoint = ground
        case .changed:
            if let last = lastPanPoint {
                manual.translate(by: Vec2(x: Double(ground.x - last.x), z: Double(ground.z - last.z)))
            }
            lastPanPoint = ground
        default:
            lastPanPoint = nil
            logManual("arrastre")
        }
    }

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard applied != nil, let pivot = cameraPlane else {
            return
        }
        switch gesture.state {
        case .changed:
            // Mirando al suelo, girar los dedos en el sentido de las agujas
            // lleva el este hacia el sur: un giro positivo del plano.
            manual.rotate(by: Double(gesture.rotation), around: pivot)
            gesture.rotation = 0
        case .ended, .cancelled:
            logManual("giro")
        default:
            break
        }
    }

    private func logManual(_ what: String) {
        let t = manual.transform
        AppLog.shared.write(
            String(format: "Corrección manual (%@): giro %.1f°, desplazamiento %.1f, %.1f m",
                   what, t.theta * 180 / .pi, t.t.x, t.t.z),
            category: "ar"
        )
    }

    /// Punto del suelo (en el mundo de ARKit) que hay bajo un punto de la pantalla.
    private func groundPoint(at screen: CGPoint) -> SIMD3<Float>? {
        guard let camera = cameraTransform, let ray = arView.ray(through: screen) else {
            return nil
        }
        let groundY = controller.groundHeight(camera: camera, dt: 0)
        guard ray.direction.y < -0.05 else {
            return nil
        }
        let t = (groundY - ray.origin.y) / ray.direction.y
        guard t > 0, t < 150 else {
            return nil
        }
        return ray.origin + ray.direction * t
    }

    // MARK: - Grabación

    func toggleRecording() {
        if recorder.isRecording {
            recorder.finish()
        } else if let frame = sceneFrame {
            recorder.begin(mode: controller.mode.rawValue, origin: frame.origin)
        }
    }

    private func fillPose(_ sample: inout SessionSample) {
        if let camera = cameraTransform {
            sample.arX = Double(camera.columns.3.x)
            sample.arY = Double(camera.columns.3.y)
            sample.arZ = Double(camera.columns.3.z)
            sample.groundY = Double(controller.groundHeight(camera: camera, dt: 0))
        }
        sample.tracking = controller.trackingText
        if let heading = location?.heading {
            sample.heading = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            sample.headingAccuracy = heading.headingAccuracy
        }
    }

    // MARK: - Cada imagen

    private func update(frame arFrame: ARFrame) {
        guard active else {
            return
        }
        let now = arFrame.timestamp
        let dt = lastFrameTime > 0 ? min(max(now - lastFrameTime, 0), 0.5) : 0
        lastFrameTime = now
        if dt > 0 {
            fps = fps == 0 ? 1 / dt : fps * 0.9 + (1 / dt) * 0.1
        }

        let camera = arFrame.camera.transform
        cameraTransform = camera
        let plane = Vec2(x: Double(camera.columns.3.x), z: Double(camera.columns.3.z))
        cameraPlane = plane

        guard let model = model else {
            setBlocking("Cargando los datos del metro…")
            return
        }
        if let error = controller.errorText {
            setBlocking(error)
            return
        }
        guard let frame = sceneFrame else {
            if location?.authorization == .denied || location?.authorization == .restricted {
                setBlocking("Sin permiso de ubicación. Actívalo en Ajustes para colocar el túnel.")
            } else {
                setBlocking("Buscando señal GPS… Sal a cielo abierto.")
            }
            return
        }

        // 1. Ajuste automático.
        var automatic: RigidTransform2D?
        if controller.mode == .geo {
            if !controller.hasGeoAnchor {
                // El Modo A puede arrancar después de fijar el origen.
                controller.setGeoOrigin(
                    CLLocationCoordinate2D(latitude: frame.origin.latitude, longitude: frame.origin.longitude)
                )
            }
            if let anchor = controller.geoOriginTransform {
                // El eje x del ancla es el este: su dirección en el mundo da el giro.
                let east = anchor.columns.0
                automatic = RigidTransform2D(
                    theta: atan2(Double(east.z), Double(east.x)),
                    t: Vec2(x: Double(anchor.columns.3.x), z: Double(anchor.columns.3.z))
                )
            }
        } else {
            estimator.track(ar: plane)
            if let target = estimator.transform ?? bootstrap {
                automatic = smoother.step(toward: target, userAR: plane, dt: dt)
            }
        }
        guard let automatic = automatic else {
            if controller.mode == .geo {
                setBlocking("Geotracking: \(controller.geoText). Apunta el iPhone a los edificios de alrededor.")
            } else if controller.trackingLimited {
                setBlocking("Iniciando ARKit… Mueve el móvil despacio.")
            } else {
                setBlocking("Esperando una lectura de GPS…")
            }
            builder.root.isEnabled = false
            return
        }
        applied = automatic
        let final = manual.applied(to: automatic)

        // 2. Dónde está el usuario según el ajuste.
        let userPlane = final.inverse(plane)
        let geo = frame.geo(userPlane)
        userGeo = geo

        // 3. Consultas lentas, dos veces por segundo.
        if now - lastSlowUpdate > 0.5 {
            lastSlowUpdate = now
            slowUpdate(model: model, geo: geo)
        }

        // 4. Altura: el suelo detectado por ARKit bajo el usuario corresponde
        // a la cota del suelo en ese punto, más lo que estés por encima del
        // terreno si pisas un puente o una pasarela.
        let groundW = controller.groundHeight(camera: camera, dt: Float(dt))
        let lift = targetLift
        if appliedHeight == nil {
            appliedLift = lift
        } else {
            // La del GPS entra despacio; la puesta a mano, enseguida.
            appliedLift += (lift - appliedLift) * min(dt * (manualLift == nil ? 1.5 : 8), 1)
        }
        let groundCota = (userGround ?? frame.cotaRef) + appliedLift
        let targetHeight = groundW - frame.height(ofCota: groundCota)
        let height: Float
        if let current = appliedHeight, abs(current - targetHeight) < 5 {
            height = current + (targetHeight - current) * Float(min(dt * 1.5, 1))
        } else {
            height = targetHeight
        }
        appliedHeight = height

        // 5. Colocar la escena en el mundo de ARKit.
        builder.root.transform = Transform(
            scale: SIMD3<Float>(1, 1, 1),
            rotation: simd_quatf(angle: Float(final.yawAroundY), axis: SIMD3<Float>(0, 1, 0)),
            translation: SIMD3<Float>(Float(final.t.x), height, Float(final.t.z))
        )
        builder.root.isEnabled = true
        if blockingMessage != nil {
            blockingMessage = nil
        }
        if !loggedFirstPlacement {
            loggedFirstPlacement = true
            AppLog.shared.write(
                String(format: "Túnel colocado (modo %@): giro %.1f°, usuario en %.6f, %.6f",
                       controller.mode.rawValue, final.theta * 180 / .pi, geo.latitude, geo.longitude),
                category: "ar"
            )
        }

        // 6. Contenido.
        builder.buildPending(model: model)
        builder.grid.update(user: userPlane, height: frame.height(ofCota: groundCota))

        if usesRealtime, now - lastTrainUpdate > 0.1, let locator = locator, let realtime = realtime {
            lastTrainUpdate = now
            builder.updateTrains(realtime.trains(locator: locator), model: model, userGeo: geo)
        }

        if now - lastLabelUpdate > 0.1 {
            lastLabelUpdate = now
            var items = builder.stationLabels
            if let depth = builder.depthLabel {
                items.append(depth)
            }
            let projected = LabelProjector.project(items, root: builder.root, arView: arView, camera: camera)
            if projected != labels {
                labels = projected
            }
        }

        // 7. Grabación: una muestra de pose por segundo además de las de GPS.
        if recorder.isRecording, now - lastRecorderSample > 1 {
            lastRecorderSample = now
            recorder.add { sample in
                self.fillPose(&sample)
            }
        }
    }

    private func setBlocking(_ message: String) {
        if blockingMessage != message {
            blockingMessage = message
        }
        if !labels.isEmpty {
            labels = []
        }
        refreshHUD()
    }

    /// Consultas que no hace falta repetir en cada imagen.
    private func slowUpdate(model: MetroModel, geo: GeoPoint) {
        userGround = model.groundElevation(at: geo)
        let station = model.nearestStation(to: geo)
        let track = model.nearestTrack(to: geo)
        nearestTrack = track

        // La escena se regenera al alejarse 50 m del último centro.
        if lastRefreshCenter == nil || Geo.distance(from: lastRefreshCenter!, to: geo) > 50 {
            lastRefreshCenter = geo
            builder.refresh(model: model, userGeo: geo)
        }
        builder.updateDepthLine(track: track, userGround: userGround)

        var newSummary = ARSummary()
        newSummary.estacion = station?.estacion.nombre
        newSummary.distanciaEstacion = station?.distance
        newSummary.distanciaVia = track?.distance
        if let track = track, let ground = userGround {
            // Bajo tus pies: cuenta también lo que estés sobre el terreno.
            newSummary.profundidad = ground + targetLift - track.point.cotaCarril
        }
        // En metros enteros, para no redibujar el panel con cada lectura.
        newSummary.altura = targetLift.rounded()
        newSummary.alturaManual = manualLift != nil
        newSummary.profundidadEstimada = station?.estacion.origenCota == .estimado
        if newSummary != summary {
            summary = newSummary
        }

        let bocas = model.nearestBocas(to: geo, count: 3)
        if bocas != nearbyBocas {
            nearbyBocas = bocas
        }

        var input = AdvisoryInput()
        if let location = location {
            input.hasLocationPermission = location.authorization != .denied && location.authorization != .restricted
            input.reducedAccuracy = location.reducedAccuracy
            input.gpsAccuracy = location.location?.horizontalAccuracy
            input.headingAccuracy = location.heading?.headingAccuracy
        }
        input.trackingLimited = controller.trackingLimited
        input.dependsOnCompass = controller.mode == .manual && !estimator.rotationSolved
        input.anchored = estimator.hasAnchor || controller.mode == .geo
        input.distanceToTrack = track?.distance ?? 10_000
        input.trainsOffline = usesRealtime && (realtime?.offline ?? false)
        let newAdvisories = Advisories.evaluate(input)
        if newAdvisories != advisories {
            advisories = newAdvisories
            if !newAdvisories.isEmpty {
                AppLog.shared.write("Avisos: " + newAdvisories.map { $0.rawValue }.joined(separator: ", "), category: "ar")
            }
        }
        refreshHUD()
    }

    private func refreshHUD() {
        var state = HUDState()
        state.mode = controller.mode.rawValue
        state.tracking = controller.trackingText
        state.geo = controller.geoText
        state.gpsAccuracy = location?.location?.horizontalAccuracy
        state.heading = location?.headingDegrees
        state.headingAccuracy = location?.heading?.headingAccuracy
        state.fps = fps
        state.entities = builder.entityCount
        state.pendingChunks = builder.pendingChunks
        state.trains = builder.trainCount
        state.planes = controller.planeCount
        state.pairs = estimator.pairs.count
        state.spread = estimator.spread
        if let applied = applied {
            state.thetaDegrees = manual.applied(to: applied).theta * 180 / .pi
        }
        state.rotationFromPath = estimator.rotationSolved
        state.anchored = estimator.hasAnchor || anchoredAt != nil
        state.manual = !manual.isIdentity
        if let camera = cameraTransform {
            state.cameraHeight = Double(camera.columns.3.y - controller.groundHeight(camera: camera, dt: 0))
        }
        state.lift = targetLift
        state.liftManual = manualLift != nil
        if let fix = location?.location {
            state.altitude = fix.altitude
            state.altitudeAccuracy = fix.verticalAccuracy
        }
        state.latitude = userGeo?.latitude
        state.longitude = userGeo?.longitude
        if state != hud {
            hud = state
        }
    }
}
