import SwiftUI

/// Pantalla de bienvenida: explica qué hace la app y para qué pide cada
/// permiso antes de que salgan los avisos del sistema.
struct OnboardingScreen: View {
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                    Text("Metro Bilbao Rayos X")
                        .font(.largeTitle.weight(.bold))
                    Text("Apunta el iPhone al suelo y mira el túnel del metro bajo tus pies, a su profundidad real.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Text("El móvil no detecta nada bajo tierra: coloca un modelo del trazado usando el GPS, la brújula y la cámara. Por eso funciona en la calle, a cielo abierto, y acierta más si te anclas en una boca de metro.")
                    .font(.callout)

                VStack(alignment: .leading, spacing: 16) {
                    PermissionRow(
                        systemImage: "location.fill",
                        title: "Ubicación",
                        text: "Para saber dónde estás y colocar el túnel. Elige «Ubicación exacta»."
                    )
                    PermissionRow(
                        systemImage: "camera.fill",
                        title: "Cámara",
                        text: "Para dibujar el túnel sobre lo que ves. La imagen no sale del iPhone."
                    )
                    PermissionRow(
                        systemImage: "barometer",
                        title: "Movimiento",
                        text: "Solo en el modo medición: el barómetro mide cuánto bajas de la boca al andén."
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Ten cuidado", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text("Párate para mirar la pantalla y no cruces la calle mirando el móvil. La realidad aumentada calienta el teléfono y gasta batería.")
                        .font(.callout)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(action: onStart) {
                    Text("Empezar")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
        .interactiveDismissDisabled()
    }
}

private struct PermissionRow: View {
    let systemImage: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
}
