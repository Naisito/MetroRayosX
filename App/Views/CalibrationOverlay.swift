import MetroCore
import SwiftUI

/// Panel de calibración: anclaje en una boca, reinicio y recordatorio de los
/// gestos. Los gestos (un dedo mueve, dos dedos giran) funcionan siempre
/// sobre la imagen, con el panel abierto o cerrado.
struct CalibrationOverlay: View {
    @ObservedObject var experience: ARExperience
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Calibrar")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            Text("Ponte en la entrada de una estación y pulsa su botón. Es lo más preciso y conviene hacerlo al empezar.")
                .font(.caption)
                .foregroundColor(.secondary)

            if experience.nearbyBocas.isEmpty {
                Text("No hay bocas a menos de 400 m.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ForEach(experience.nearbyBocas) { boca in
                    Button {
                        experience.anchor(at: boca)
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Estoy en esta boca")
                                    .font(.subheadline.weight(.semibold))
                                Text(title(for: boca))
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(GeoFormat.meters(boca.distance))
                                .font(.callout.monospacedDigit())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 14) {
                Label("Un dedo mueve", systemImage: "hand.draw")
                Label("Dos dedos giran", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Button(role: .destructive) {
                experience.restart()
            } label: {
                Label("Reiniciar la alineación", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func title(for boca: BocaCercana) -> String {
        if boca.boca.nombre.isEmpty || boca.boca.nombre == boca.estacion.nombre {
            return boca.estacion.nombre
        }
        return "\(boca.estacion.nombre) · \(boca.boca.nombre)"
    }
}
