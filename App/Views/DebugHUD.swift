import SwiftUI

/// Panel de depuración de la pantalla AR: precisión del GPS, estado del
/// seguimiento, rumbo, número de entidades e imágenes por segundo.
struct DebugHUD: View {
    let state: HUDState
    @ObservedObject var recorder: SessionRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.self) { line in
                Text(line)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
    }

    private var lines: [String] {
        var result: [String] = []
        var modeLine = "Modo \(state.mode) · AR: \(state.tracking)"
        if !state.geo.isEmpty {
            modeLine += " · geo: \(state.geo)"
        }
        result.append(modeLine)

        let gps = state.gpsAccuracy.map { String(format: "±%.0f m", $0) } ?? "sin dato"
        var heading = "sin dato"
        if let degrees = state.heading {
            heading = String(format: "%.0f°", degrees)
            if let accuracy = state.headingAccuracy {
                heading += String(format: " ±%.0f°", accuracy)
            }
        }
        result.append("GPS \(gps) · rumbo \(heading)")

        result.append(
            String(
                format: "%.0f img/s · %d entidades (+%d) · %d trenes · %d planos",
                state.fps, state.entities, state.pendingChunks, state.trains, state.planes
            )
        )
        result.append(
            String(
                format: "Ajuste: giro %.1f° (%@) · %d parejas · %.0f m andados",
                state.thetaDegrees,
                state.rotationFromPath ? "trayectoria" : "brújula",
                state.pairs,
                state.spread
            )
        )
        var flags: [String] = []
        if state.anchored {
            flags.append("anclado")
        }
        if state.manual {
            flags.append("corrección manual")
        }
        flags.append(String(format: "móvil a %.1f m del suelo", state.cameraHeight))
        result.append(flags.joined(separator: " · "))

        if let latitude = state.latitude, let longitude = state.longitude {
            result.append(String(format: "Posición ajustada: %.6f, %.6f", latitude, longitude))
        }
        if recorder.isRecording {
            result.append("● Grabando: \(recorder.sampleCount) muestras")
        }
        return result
    }
}
