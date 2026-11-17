import CoreLocation
import MetroCore
import SwiftUI

/// Modo medición: mide con el barómetro lo que se baja de la boca al andén
/// y produce la fila de esa estación para `tools/depths.csv`.
struct MeasureScreen: View {
    @EnvironmentObject private var store: NetworkStore
    @EnvironmentObject private var location: LocationService
    @StateObject private var altimeter = AltimeterService()

    @State private var selectedID = ""
    @State private var startCota: Double?
    @State private var startDescription = ""
    @State private var lastResult: DepthMeasurement?
    @State private var savedRows: [String] = []
    @State private var sharedFile: SharedFile?

    var body: some View {
        NavigationView {
            Form {
                if let model = store.model {
                    stationSection(model)
                    measureSection(model)
                    if let result = lastResult {
                        resultSection(result)
                    }
                    savedSection
                } else {
                    Text(store.errorText ?? "Cargando la red del metro…")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Medir profundidad")
        }
        .navigationViewStyle(.stack)
        .onAppear {
            location.start()
            savedRows = MeasureScreen.loadRows()
            selectNearestIfNeeded()
        }
        .onDisappear {
            altimeter.stop()
        }
        .sheet(item: $sharedFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    // MARK: - Estación

    private func stationSection(_ model: MetroModel) -> some View {
        Section(
            header: Text("Estación"),
            footer: Text("Por defecto, la más cercana. Solo tiene sentido medir las subterráneas.")
        ) {
            Picker("Estación", selection: $selectedID) {
                ForEach(sortedStations(model), id: \.id) { estacion in
                    Text(estacion.nombre + (estacion.subterranea ? "" : " (superficie)"))
                        .tag(estacion.id)
                }
            }
            if let estacion = selected(model) {
                HStack {
                    Text("Profundidad actual")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f m (%@)", estacion.profundidad, estacion.origenCota.rawValue))
                        .font(.body.monospacedDigit())
                }
            }
        }
    }

    private func sortedStations(_ model: MetroModel) -> [Estacion] {
        model.red.estaciones.sorted { $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending }
    }

    private func selected(_ model: MetroModel) -> Estacion? {
        model.red.estaciones.first { $0.id == selectedID }
    }

    private func selectNearestIfNeeded() {
        guard selectedID.isEmpty, let model = store.model else {
            return
        }
        if let fix = location.location {
            let here = GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
            selectedID = model.nearestStation(to: here)?.estacion.id ?? ""
        }
        if selectedID.isEmpty {
            selectedID = sortedStations(model).first?.id ?? ""
        }
    }

    // MARK: - Medición

    private func measureSection(_ model: MetroModel) -> some View {
        Section(
            header: Text("Medición"),
            footer: Text("Pulsa Inicio en la boca, a pie de calle. Baja al andén sin entretenerte y pulsa Fin junto a la vía. Lleva el móvil a la misma altura al empezar y al acabar.")
        ) {
            if altimeter.isRunning {
                HStack {
                    Text("Has bajado")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(descentText)
                        .font(.title2.weight(.bold).monospacedDigit())
                }
                if !startDescription.isEmpty {
                    Text(startDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button {
                    finish(model)
                } label: {
                    Label("Fin: estoy en el andén", systemImage: "stop.circle.fill")
                }
                Button(role: .destructive) {
                    altimeter.stop()
                    AppLog.shared.write("Medición cancelada", category: "medir")
                } label: {
                    Label("Cancelar", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    begin(model)
                } label: {
                    Label("Inicio: estoy en la boca", systemImage: "play.circle.fill")
                }
                .disabled(selectedID.isEmpty || !altimeter.isAvailable)
            }
            if let error = altimeter.errorText {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.red)
            } else if !altimeter.isAvailable {
                Text("Este iPhone no tiene barómetro.")
                    .font(.callout)
                    .foregroundColor(.red)
            }
        }
    }

    private var descentText: String {
        guard let altitude = altimeter.relativeAltitude else {
            return "…"
        }
        return String(format: "%.1f m", -altitude)
    }

    private func begin(_ model: MetroModel) {
        lastResult = nil
        startCota = nil
        startDescription = ""

        // Cota de la boca: la de la boca de esa estación que esté al lado y,
        // si no hay ninguna, la del relieve donde está el usuario.
        if let fix = location.location, let estacion = selected(model) {
            let here = GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
            let near = estacion.bocas
                .map { (boca: $0, distance: Geo.distance(from: here, to: $0.geo)) }
                .filter { $0.distance < 40 }
                .min { $0.distance < $1.distance }
            if let near = near {
                startCota = near.boca.cotaSuelo
                startDescription = String(
                    format: "Boca a %.0f m de ti, suelo a %.1f m de cota.", near.distance, near.boca.cotaSuelo
                )
            } else if let ground = model.groundElevation(at: here) {
                startCota = ground
                startDescription = String(
                    format: "No estás junto a una boca de esta estación: se usa la cota del suelo donde estás (%.1f m).",
                    ground
                )
            }
        }
        if startCota == nil {
            startDescription = "Sin posición: la fila llevará el desnivel pero no la cota de la boca."
        }
        AppLog.shared.write("Medición iniciada en \(selectedID). \(startDescription)", category: "medir")
        altimeter.start()
    }

    private func finish(_ model: MetroModel) {
        guard let altitude = altimeter.relativeAltitude, let estacion = selected(model) else {
            altimeter.stop()
            return
        }
        altimeter.stop()
        let measurement = DepthMeasurement(
            stopID: estacion.id,
            nombre: estacion.nombre,
            desnivel: -altitude,
            cotaBoca: startCota,
            fecha: DepthMeasurement.today()
        )
        lastResult = measurement
        MeasureScreen.append(measurement.csvRow)
        savedRows = MeasureScreen.loadRows()
        AppLog.shared.write("Medición guardada: \(measurement.csvRow)", category: "medir")
    }

    // MARK: - Resultado

    private func resultSection(_ result: DepthMeasurement) -> some View {
        Section(header: Text("Resultado")) {
            HStack {
                Text("Desnivel medido")
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f m", result.desnivel))
                    .font(.body.monospacedDigit())
            }
            if let rail = result.cotaCarril {
                HStack {
                    Text("Cota del carril")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f m", rail))
                        .font(.body.monospacedDigit())
                }
            }
            Text(result.csvRow)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var savedSection: some View {
        Section(
            header: Text("Mediciones guardadas"),
            footer: Text("Comparte el fichero y pásaselo a Claude Code para añadir las filas a tools/depths.csv.")
        ) {
            if savedRows.isEmpty {
                Text("Todavía no hay ninguna.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(savedRows.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.system(.caption2, design: .monospaced))
                }
                Button {
                    sharedFile = SharedFile(url: MeasureScreen.fileURL)
                } label: {
                    Label("Compartir mediciones.csv", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Fichero

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mediciones.csv")
    }

    /// Filas guardadas, sin la cabecera.
    static func loadRows() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .map { String($0) }
    }

    static func append(_ row: String) {
        var text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        if text.isEmpty {
            text = DepthMeasurement.csvHeader + "\n"
        }
        if !text.hasSuffix("\n") {
            text += "\n"
        }
        text += row + "\n"
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            AppLog.shared.write("No se pudo guardar mediciones.csv: \(error)", category: "medir")
        }
    }
}
