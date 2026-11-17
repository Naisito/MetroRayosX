import MetroCore
import SwiftUI

/// Atribuciones de los datos y límites de la app.
struct AboutScreen: View {
    @EnvironmentObject private var store: NetworkStore

    var body: some View {
        List {
            Section(header: Text("Qué es")) {
                Text("Metro Bilbao Rayos X dibuja el trazado del metro en realidad aumentada, bajo tus pies. No detecta nada bajo tierra: coloca un modelo hecho con datos abiertos usando el GPS, la brújula y ARKit.")
                Text("Es un proyecto personal, sin relación con Metro Bilbao, el Consorcio de Transportes de Bizkaia ni Euskotren.")
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Datos"), footer: Text(dataFooter)) {
                Attribution(
                    title: "Trazado de las vías y bocas",
                    source: "© OpenStreetMap contributors",
                    license: "Open Database License (ODbL)",
                    link: "https://www.openstreetmap.org/copyright"
                )
                Attribution(
                    title: "Estaciones y horarios",
                    source: "Metro Bilbao, datos abiertos",
                    license: "Publicados por el CTB con licencia CC BY 4.0",
                    link: "https://www.metrobilbao.eus/es/open-data"
                )
                Attribution(
                    title: "Trenes en vivo",
                    source: "Consorcio de Transportes de Bizkaia (CTB)",
                    license: "Feeds GTFS-Realtime, CC BY 4.0",
                    link: "https://data.ctb.eus"
                )
                Attribution(
                    title: "Relieve",
                    source: "geoEuskadi, MDT LiDAR 2017",
                    license: "CC BY 4.0",
                    link: "https://www.geo.euskadi.eus"
                )
            }

            Section(header: Text("Límites")) {
                Label("Funciona en la calle. Dentro del metro no hay GPS.", systemImage: "location.slash")
                Label("La posición horizontal acierta unos pocos metros, más si te anclas en una boca.", systemImage: "scope")
                Label("La profundidad de las estaciones subterráneas es una estimación (20 m bajo la boca) hasta que se mida. Entre estaciones se interpola.", systemImage: "ruler")
                Label("Los trenes se colocan con las horas de llegada del feed: dentro del túnel no hay posición real.", systemImage: "tram")
                Label("La línea 3 se dibuja, pero no tiene trenes en vivo.", systemImage: "3.circle")
            }

            Section(header: Text("Versión")) {
                AboutRow(label: "App", value: "\(AppInfo.version) (build \(AppInfo.build))")
                AboutRow(label: "Commit", value: AppInfo.commit)
                if let red = store.model?.red {
                    AboutRow(label: "Datos generados", value: red.generado)
                    AboutRow(label: "Vías", value: "\(red.vias.count) tramos")
                    AboutRow(label: "Estaciones", value: "\(red.estaciones.count)")
                }
            }
        }
        .navigationTitle("Acerca de")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dataFooter: String {
        guard let red = store.model?.red else {
            return ""
        }
        let measured = red.estaciones.filter { $0.subterranea && $0.origenCota != .estimado }.count
        let underground = red.estaciones.filter { $0.subterranea }.count
        return "Profundidad medida en \(measured) de \(underground) estaciones subterráneas."
    }
}

private struct Attribution: View {
    let title: String
    let source: String
    let license: String
    let link: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(source)
            Text(license)
                .font(.caption)
                .foregroundColor(.secondary)
            if let url = URL(string: link) {
                Link(link, destination: url)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AboutRow: View {
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
    }
}
