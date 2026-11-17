import CoreLocation
import MapKit
import MetroCore
import SwiftUI

/// Mapa 2D con las vías por color de línea, estaciones, bocas, tu posición
/// y los trenes en vivo.
struct MapScreen: View {
    @EnvironmentObject private var store: NetworkStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var realtime: RealtimeService

    @AppStorage("trenesActivados") private var showTrains = true
    @AppStorage("bienvenidaVista") private var welcomed = false
    @State private var recenterToken = 0
    @State private var trains: [TrainMarker] = []
    @State private var locator: TrainLocator?
    @State private var usingRealtime = false

    private let clock = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            if let model = store.model {
                MetroMapView(
                    model: model,
                    trains: showTrains ? trains : [],
                    recenterToken: recenterToken,
                    userLocation: location.location
                )
                .ignoresSafeArea(edges: .top)
            } else if let error = store.errorText {
                Text(error)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Cargando la red del metro…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    MapButton(systemImage: "tram.fill", active: showTrains) {
                        showTrains.toggle()
                    }
                    MapButton(systemImage: "location.fill", active: false) {
                        recenterToken += 1
                    }
                }
                infoPanel
            }
            .padding(10)
        }
        .onAppear {
            // Con la bienvenida a la vista, el permiso se pide al cerrarla.
            if welcomed {
                location.start()
            }
            updateRealtime()
        }
        .onDisappear {
            if usingRealtime {
                usingRealtime = false
                realtime.release()
            }
        }
        .onChange(of: showTrains) { _ in
            updateRealtime()
        }
        .onReceive(clock) { _ in
            refreshTrains()
        }
    }

    private func updateRealtime() {
        if showTrains, !usingRealtime {
            usingRealtime = true
            realtime.retain()
        } else if !showTrains, usingRealtime {
            usingRealtime = false
            realtime.release()
            trains = []
        }
    }

    private func refreshTrains() {
        guard showTrains, usingRealtime, let model = store.model else {
            return
        }
        if locator == nil {
            locator = TrainLocator(model: model)
        }
        guard let locator = locator else {
            return
        }
        trains = realtime.trains(locator: locator).compactMap { train in
            guard train.rutaIndex < model.rutas.count else {
                return nil
            }
            let route = model.rutas[train.rutaIndex]
            let point = route.point(at: train.chainage)
            return TrainMarker(
                id: train.id,
                latitude: point.lat,
                longitude: point.lon,
                colorHex: model.colorHex(ofLine: train.linea ?? route.ruta.linea),
                destino: route.ruta.nombre
            )
        }
    }

    // MARK: - Panel inferior

    @ViewBuilder
    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let model = store.model, let fix = location.location {
                let here = GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
                let summary = model.summary(at: here)
                let boca = model.nearestBocas(to: here, count: 1, maxDistance: 2000).first

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.estacion?.nombre ?? "Sin estación cerca")
                            .font(.headline)
                        if let distance = summary.distanciaEstacion {
                            Text("Estación más cercana, a \(GeoFormat.meters(distance))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text(String(format: "GPS ±%.0f m", max(fix.horizontalAccuracy, 0)))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(fix.horizontalAccuracy <= 20 ? .secondary : .orange)
                }

                if let boca = boca {
                    PanelRow(label: "Boca más cercana", value: GeoFormat.meters(boca.distance))
                }
                if let track = summary.via {
                    PanelRow(label: "Distancia a la vía", value: GeoFormat.meters(track.distance))
                    if let depth = summary.profundidad {
                        if depth > 1 {
                            PanelRow(
                                label: "Metro bajo tus pies",
                                value: String(format: "%.0f m", depth)
                                    + (summary.profundidadEstimada ? " (estimado)" : "")
                            )
                        } else {
                            PanelRow(label: "Metro bajo tus pies", value: "va por la superficie")
                        }
                    }
                } else {
                    Text("No hay vías a menos de 500 m.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } else if store.model != nil {
                Text(waitingText)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            if showTrains {
                Text(trainsText)
                    .font(.caption2)
                    .foregroundColor(realtime.offline ? .orange : .secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var waitingText: String {
        switch location.authorization {
        case .denied, .restricted:
            return "Sin permiso de ubicación. Actívalo en Ajustes para saber qué hay bajo tus pies."
        case .notDetermined:
            return "Esperando el permiso de ubicación…"
        default:
            return "Buscando señal GPS…"
        }
    }

    private var trainsText: String {
        if realtime.offline {
            return Advisory.sinTrenes.mensaje
        }
        if realtime.lastSuccess == nil {
            return "Descargando los trenes en vivo…"
        }
        return "\(trains.count) trenes en circulación (L1 y L2, datos del CTB)"
    }
}

/// Un tren para pintar en el mapa.
struct TrainMarker: Identifiable, Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
    let colorHex: String
    let destino: String
}

private struct PanelRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
        }
        .font(.subheadline)
    }
}

private struct MapButton: View {
    let systemImage: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(active ? .white : .accentColor)
                .frame(width: 42, height: 42)
                .background(
                    active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Material.regular),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MKMapView

private final class StationAnnotation: MKPointAnnotation {
    var colorHex = "#ff7a00"
}

private final class BocaAnnotation: MKPointAnnotation {}

private final class TrainAnnotation: MKPointAnnotation {
    var trainID = ""
    var colorHex = "#ff7a00"
}

private struct MetroMapView: UIViewRepresentable {
    let model: MetroModel
    let trains: [TrainMarker]
    let recenterToken: Int
    let userLocation: CLLocation?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll

        addTracks(to: map, coordinator: context.coordinator)
        addStations(to: map)

        // Arranca en el centro de Bilbao; se centra en el usuario cuando hay posición.
        let center = CLLocationCoordinate2D(latitude: 43.2627, longitude: -2.9335)
        map.setRegion(
            MKCoordinateRegion(center: center, latitudinalMeters: 3500, longitudinalMeters: 3500),
            animated: false
        )
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Centrar en el usuario la primera vez que hay posición y cuando se pide.
        if let location = userLocation,
           !coordinator.centeredOnUser || coordinator.lastRecenterToken != recenterToken {
            coordinator.centeredOnUser = true
            coordinator.lastRecenterToken = recenterToken
            map.setRegion(
                MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 700, longitudinalMeters: 700),
                animated: true
            )
        }

        // Trenes: se mueven las anotaciones que ya existen.
        var wanted = Set<String>()
        for train in trains {
            wanted.insert(train.id)
            let coordinate = CLLocationCoordinate2D(latitude: train.latitude, longitude: train.longitude)
            if let annotation = coordinator.trainAnnotations[train.id] {
                UIView.animate(withDuration: 1.9, delay: 0, options: [.curveLinear, .allowUserInteraction]) {
                    annotation.coordinate = coordinate
                }
            } else {
                let annotation = TrainAnnotation()
                annotation.trainID = train.id
                annotation.colorHex = train.colorHex
                annotation.coordinate = coordinate
                annotation.title = "Tren"
                annotation.subtitle = train.destino
                coordinator.trainAnnotations[train.id] = annotation
                map.addAnnotation(annotation)
            }
        }
        for (id, annotation) in coordinator.trainAnnotations where !wanted.contains(id) {
            map.removeAnnotation(annotation)
            coordinator.trainAnnotations.removeValue(forKey: id)
        }
    }

    /// Una capa por color de línea y por tipo de tramo (túnel o superficie).
    private func addTracks(to map: MKMapView, coordinator: Coordinator) {
        struct Group {
            var polylines: [MKPolyline] = []
            var colorHex = ""
            var tunnel = false
            var order = 0
        }
        var groups: [String: Group] = [:]
        let lineOrder = model.red.lineas.map { $0.id }

        for via in model.red.vias {
            let colorHex = model.colorHex(of: via)
            let key = "\(colorHex)|\(via.tunel)"
            var coordinates = via.puntos.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            var group = groups[key] ?? Group()
            group.polylines.append(polyline)
            group.colorHex = colorHex
            group.tunnel = via.tunel
            group.order = via.lineas.first.flatMap { lineOrder.firstIndex(of: $0) } ?? 99
            groups[key] = group
        }

        // La primera línea (L1) se pinta la última, encima de las demás.
        for group in groups.values.sorted(by: { $0.order > $1.order }) {
            let overlay = MKMultiPolyline(group.polylines)
            coordinator.styles[ObjectIdentifier(overlay)] = Coordinator.Style(
                colorHex: group.colorHex, tunnel: group.tunnel
            )
            map.addOverlay(overlay, level: .aboveRoads)
        }
    }

    private func addStations(to map: MKMapView) {
        var annotations: [MKAnnotation] = []
        for estacion in model.red.estaciones {
            let station = StationAnnotation()
            station.coordinate = CLLocationCoordinate2D(latitude: estacion.lat, longitude: estacion.lon)
            station.title = estacion.nombre
            if estacion.subterranea {
                station.subtitle = String(format: "%.0f m bajo el suelo", estacion.profundidad)
                    + (estacion.origenCota == .estimado ? " (estimado)" : "")
            } else {
                station.subtitle = "En superficie"
            }
            station.colorHex = model.colorHex(ofLine: estacion.lineas.first)
            annotations.append(station)

            for boca in estacion.bocas {
                let annotation = BocaAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(latitude: boca.lat, longitude: boca.lon)
                annotation.title = boca.nombre.isEmpty ? "Boca" : boca.nombre
                annotation.subtitle = "Boca de " + estacion.nombre
                annotations.append(annotation)
            }
        }
        map.addAnnotations(annotations)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        struct Style {
            let colorHex: String
            let tunnel: Bool
        }

        var styles: [ObjectIdentifier: Style] = [:]
        var trainAnnotations: [String: TrainAnnotation] = [:]
        var centeredOnUser = false
        var lastRecenterToken = 0

        private func color(_ hex: String) -> UIColor {
            // El negro de la L2 se cambia por el color de texto, que se ve
            // tanto en el mapa claro como en el oscuro.
            guard let rgb = ColorHex.rgb(hex) else {
                return .systemOrange
            }
            if rgb.r + rgb.g + rgb.b < 0.3 {
                return .label
            }
            return UIColor(red: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), alpha: 1)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let multi = overlay as? MKMultiPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKMultiPolylineRenderer(multiPolyline: multi)
            let style = styles[ObjectIdentifier(multi)]
            renderer.strokeColor = color(style?.colorHex ?? "#ff7a00")
            renderer.lineWidth = 3
            renderer.lineCap = .round
            // Bajo tierra, línea discontinua.
            if style?.tunnel == true {
                renderer.lineDashPattern = [6, 5]
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let station = annotation as? StationAnnotation {
                let identifier = "estacion"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.markerTintColor = color(station.colorHex)
                view.glyphText = "M"
                view.titleVisibility = .adaptive
                view.displayPriority = .required
                view.canShowCallout = true
                return view
            }
            if annotation is BocaAnnotation {
                let identifier = "boca"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.image = Coordinator.dot(diameter: 11, fill: .systemGreen)
                view.displayPriority = .defaultLow
                view.canShowCallout = true
                return view
            }
            if let train = annotation as? TrainAnnotation {
                let identifier = "tren"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.image = Coordinator.dot(diameter: 18, fill: color(train.colorHex))
                view.displayPriority = .required
                view.canShowCallout = true
                view.layer.zPosition = 10
                return view
            }
            return nil
        }

        /// Círculo con borde blanco.
        static func dot(diameter: CGFloat, fill: UIColor) -> UIImage {
            let size = CGSize(width: diameter, height: diameter)
            return UIGraphicsImageRenderer(size: size).image { context in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
                fill.setFill()
                UIColor.white.setStroke()
                context.cgContext.setLineWidth(2)
                context.cgContext.fillEllipse(in: rect)
                context.cgContext.strokeEllipse(in: rect)
            }
        }
    }
}
