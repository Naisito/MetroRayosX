import CoreLocation
import MetroCore
import SwiftUI
import UIKit

/// Estado del iPhone: posición, rumbo, cobertura de geotracking y registro.
/// Era la pantalla única de la Fase 0; ahora cuelga de la pestaña «Más».
struct StatusScreen: View {
    @EnvironmentObject private var location: LocationService
    @ObservedObject private var appLog = AppLog.shared
    @StateObject private var probe = GeoTrackingProbe()
    @State private var showingShare = false

    var body: some View {
        List {
            positionSection
            headingSection
            geoTrackingSection
            logSection
            appSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Estado y registro")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            location.start()
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(items: [appLog.fileURL])
        }
    }

    // MARK: - Posición

    private var positionSection: some View {
        Section(header: Text("Posición"), footer: Text(positionFooter)) {
            if let fix = location.location {
                InfoRow("Latitud", GeoFormat.degrees(fix.coordinate.latitude))
                InfoRow("Longitud", GeoFormat.degrees(fix.coordinate.longitude))
                InfoRow(
                    "Precisión del GPS",
                    fix.horizontalAccuracy >= 0 ? String(format: "±%.0f m", fix.horizontalAccuracy) : "sin dato",
                    color: accuracyColor(fix.horizontalAccuracy)
                )
                InfoRow(
                    "Altitud",
                    fix.verticalAccuracy >= 0
                        ? String(format: "%.0f m (±%.0f m)", fix.altitude, fix.verticalAccuracy)
                        : "sin dato"
                )
                ForEach(Landmarks.geoTrackingProbes) { landmark in
                    InfoRow("Hasta \(landmark.name)", GeoFormat.meters(distance(from: fix, to: landmark)))
                }
            } else {
                Text(waitingText)
                    .foregroundColor(.secondary)
                if location.authorization == .denied || location.authorization == .restricted {
                    Button("Abrir Ajustes") {
                        openSettings()
                    }
                }
            }
        }
    }

    private var waitingText: String {
        switch location.authorization {
        case .notDetermined:
            return "Esperando el permiso de ubicación…"
        case .denied, .restricted:
            return "Sin permiso de ubicación. Actívalo en Ajustes > Privacidad y seguridad > Localización."
        default:
            return "Buscando señal GPS…"
        }
    }

    private var positionFooter: String {
        if location.reducedAccuracy {
            return "La ubicación está en modo aproximado. Activa «Ubicación exacta» en los ajustes de la app."
        }
        return "Permiso de ubicación: \(location.authorizationText)."
    }

    private func distance(from fix: CLLocation, to landmark: Landmark) -> Double {
        let here = GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        return Geo.distance(from: here, to: landmark.point)
    }

    private func accuracyColor(_ meters: Double) -> Color {
        if meters < 0 {
            return .secondary
        }
        if meters <= 10 {
            return .green
        }
        if meters <= 20 {
            return .orange
        }
        return .red
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Rumbo

    private var headingSection: some View {
        Section(header: Text("Rumbo")) {
            if let degrees = location.headingDegrees, let heading = location.heading {
                InfoRow("Rumbo", String(format: "%.0f° %@", degrees, GeoFormat.cardinal(degrees)))
                InfoRow(
                    "Precisión de la brújula",
                    String(format: "±%.0f°", heading.headingAccuracy),
                    color: headingColor(heading.headingAccuracy)
                )
                InfoRow("Referencia", location.headingIsTrueNorth ? "norte verdadero" : "norte magnético")
            } else {
                Text("Sin rumbo todavía. Mueve el iPhone dibujando un ocho.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func headingColor(_ degrees: Double) -> Color {
        if degrees <= 15 {
            return .green
        }
        if degrees <= 25 {
            return .orange
        }
        return .red
    }

    // MARK: - Geotracking

    private var geoTrackingSection: some View {
        Section(header: Text("Geotracking de ARKit"), footer: Text(geoTrackingFooter)) {
            Button {
                probe.run(userLocation: location.location)
            } label: {
                Label("¿Hay geotracking?", systemImage: "location.viewfinder")
            }
            .disabled(probe.isRunning)

            ForEach(probe.checks) { check in
                GeoTrackingRow(check: check)
            }
        }
    }

    private var geoTrackingFooter: String {
        let device = probe.deviceSupported
            ? "Este iPhone es compatible con el geotracking."
            : "Este iPhone no es compatible con el geotracking."
        return device + " La comprobación necesita conexión a internet y el resultado queda apuntado en el registro."
    }

    // MARK: - Registro

    private var logSection: some View {
        Section(
            header: Text("Registro"),
            footer: Text("Fichero metro-rayosx.log. También está en Archivos > En mi iPhone > Metro Rayos X.")
        ) {
            Button {
                showingShare = true
            } label: {
                Label("Compartir registro", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                appLog.clear()
            } label: {
                Label("Vaciar registro", systemImage: "trash")
            }

            ForEach(recentLines, id: \.offset) { item in
                Text(item.element)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Las últimas líneas del registro, la más reciente arriba.
    private var recentLines: [(offset: Int, element: String)] {
        Array(appLog.recent.suffix(15).reversed().enumerated())
    }

    // MARK: - App

    private var appSection: some View {
        Section(header: Text("App")) {
            InfoRow("Versión", "\(AppInfo.version) (build \(AppInfo.build))")
            InfoRow("Commit", AppInfo.commit)
            InfoRow("Dispositivo", AppInfo.deviceModel)
            InfoRow("iOS", AppInfo.systemVersion)
        }
    }
}

// MARK: - Filas

private struct InfoRow: View {
    let label: String
    let value: String
    let color: Color

    init(_ label: String, _ value: String, color: Color = .primary) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundColor(color)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct GeoTrackingRow: View {
    let check: GeoTrackingCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.name)
                    Text(String(format: "%.5f, %.5f", check.point.latitude, check.point.longitude))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Spacer()
                stateView
            }
            if case .unavailable(let reason) = check.state, let reason = reason {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch check.state {
        case .checking:
            ProgressView()
        case .available:
            Label("Sí", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .unavailable:
            Label("No", systemImage: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
}
