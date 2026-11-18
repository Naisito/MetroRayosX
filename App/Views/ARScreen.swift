import MetroCore
import RealityKit
import SwiftUI

/// Pantalla de rayos X: la cámara con el túnel dibujado encima.
struct ARScreen: View {
    @EnvironmentObject private var store: NetworkStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var realtime: RealtimeService
    @StateObject private var experience = ARExperience()

    @AppStorage("trenesActivados") private var showTrains = true
    @AppStorage("panelDepuracion") private var showHUD = false
    @State private var showCalibration = false
    @State private var sharedFile: SharedFile?

    var body: some View {
        ZStack {
            ARViewContainer(arView: experience.arView)
                .ignoresSafeArea()

            LabelsOverlay(labels: experience.labels)
                .ignoresSafeArea()

            if let message = experience.blockingMessage {
                BlockingMessage(text: message)
            }

            VStack(spacing: 8) {
                AdvisoryBanner(advisories: experience.advisories)
                if showHUD {
                    DebugHUD(state: experience.hud, recorder: experience.recorder)
                }
                Spacer(minLength: 0)
                if showCalibration {
                    CalibrationOverlay(experience: experience, isPresented: $showCalibration)
                }
                bottomPanel
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .onAppear {
            experience.configure(model: store.model, location: location, realtime: realtime)
            experience.start(showTrains: showTrains)
        }
        .onDisappear {
            experience.stop()
        }
        .onReceive(store.$state) { _ in
            // Los datos pueden terminar de cargarse con la pantalla ya abierta.
            DispatchQueue.main.async {
                experience.configure(model: store.model, location: location, realtime: realtime)
            }
        }
        .onChange(of: showTrains) { enabled in
            experience.setTrains(enabled: enabled)
        }
        .sheet(item: $sharedFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    // MARK: - Panel inferior

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            summaryRow
            HStack(spacing: 10) {
                ToolButton(title: "Calibrar", systemImage: "scope", active: showCalibration) {
                    showCalibration.toggle()
                }
                ToolButton(title: "Trenes", systemImage: "tram.fill", active: showTrains) {
                    showTrains.toggle()
                }
                ToolButton(
                    title: experience.recorder.isRecording ? "Parar" : "Grabar",
                    systemImage: experience.recorder.isRecording ? "stop.circle.fill" : "record.circle",
                    active: experience.recorder.isRecording
                ) {
                    toggleRecording()
                }
                ToolButton(title: "Datos", systemImage: "ladybug", active: showHUD) {
                    showHUD.toggle()
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var summaryRow: some View {
        let summary = experience.summary
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.estacion ?? "Sin estación cerca")
                    .font(.headline)
                    .lineLimit(1)
                Text(detailText(summary))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let depth = summary.profundidad, let distance = summary.distanciaVia, distance < 60, depth > 1 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.0f m", depth))
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text(summary.profundidadEstimada ? "bajo tus pies (estimado)" : "bajo tus pies")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func detailText(_ summary: ARSummary) -> String {
        var parts: [String] = []
        if let distance = summary.distanciaEstacion {
            parts.append("estación a \(GeoFormat.meters(distance))")
        }
        if let distance = summary.distanciaVia {
            parts.append("vía a \(GeoFormat.meters(distance))")
        } else {
            parts.append("sin vías a menos de 500 m")
        }
        if abs(summary.altura) >= 1 {
            parts.append(String(format: "a %.0f m sobre el terreno", summary.altura))
        }
        if let anchored = experience.anchoredAt {
            parts.append("anclado en \(anchored)")
        }
        return parts.joined(separator: " · ")
    }

    private func toggleRecording() {
        let wasRecording = experience.recorder.isRecording
        experience.toggleRecording()
        if wasRecording, let url = experience.recorder.lastFile {
            sharedFile = SharedFile(url: url)
        }
    }
}

/// Fichero que se ofrece para compartir.
struct SharedFile: Identifiable {
    let url: URL

    var id: String {
        url.path
    }
}

private struct ARViewContainer: UIViewRepresentable {
    let arView: ARView

    func makeUIView(context: Context) -> ARView {
        arView
    }

    func updateUIView(_ view: ARView, context: Context) {}
}

/// Rótulos de estaciones, bocas y profundidad sobre la imagen.
private struct LabelsOverlay: View {
    let labels: [SceneLabel]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(labels) { label in
                LabelBubble(label: label)
                    .position(label.point)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct LabelBubble: View {
    let label: SceneLabel

    var body: some View {
        VStack(spacing: 1) {
            Text(label.title)
                .font(titleFont)
                .foregroundColor(titleColor)
            Text(label.detail)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.85))
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .fixedSize()
    }

    private var titleFont: Font {
        switch label.kind {
        case .depth:
            return .title3.weight(.bold).monospacedDigit()
        case .station:
            return .subheadline.weight(.semibold)
        case .boca:
            return .caption.weight(.semibold)
        }
    }

    private var titleColor: Color {
        switch label.kind {
        case .depth:
            return .yellow
        case .station:
            return .white
        case .boca:
            return Color(red: 0.6, green: 1.0, blue: 0.6)
        }
    }

    private var borderColor: Color {
        switch label.kind {
        case .depth:
            return .yellow.opacity(0.8)
        case .station:
            return .white.opacity(label.estimated ? 0.35 : 0.8)
        case .boca:
            return Color(red: 0.6, green: 1.0, blue: 0.6).opacity(0.6)
        }
    }
}

private struct BlockingMessage: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
        }
        .padding(18)
        .frame(maxWidth: 300)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// Avisos del plan: GPS débil, ARKit limitado, brújula imprecisa…
private struct AdvisoryBanner: View {
    let advisories: [Advisory]

    var body: some View {
        if !advisories.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(advisories, id: \.rawValue) { advisory in
                    Label(advisory.mensaje, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        }
    }
}

struct ToolButton: View {
    let title: String
    let systemImage: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundColor(active ? .white : .primary)
            .background(
                active ? Color.accentColor : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
