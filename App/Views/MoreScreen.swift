import SwiftUI

/// Pestaña «Más»: estado y registro, sesiones grabadas y atribuciones.
struct MoreScreen: View {
    @AppStorage("bienvenidaVista") private var welcomed = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink {
                        StatusScreen()
                    } label: {
                        Label("Estado y registro", systemImage: "waveform.path.ecg")
                    }
                    NavigationLink {
                        SessionsScreen()
                    } label: {
                        Label("Sesiones grabadas", systemImage: "record.circle")
                    }
                }
                Section {
                    NavigationLink {
                        AboutScreen()
                    } label: {
                        Label("Acerca de y datos", systemImage: "info.circle")
                    }
                    Button {
                        welcomed = false
                    } label: {
                        Label("Ver la bienvenida otra vez", systemImage: "hand.wave")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Más")
        }
        .navigationViewStyle(.stack)
    }
}

/// Grabaciones de GPS + AR hechas desde la pantalla de rayos X.
struct SessionsScreen: View {
    @State private var files: [URL] = []
    @State private var sharedFile: SharedFile?

    var body: some View {
        List {
            Section(
                footer: Text("Graba una sesión con el botón «Grabar» de la pantalla de rayos X cuando algo falle, y envía el fichero a Claude Code: puede reproducirla en un test sin que vuelvas a salir.")
            ) {
                if files.isEmpty {
                    Text("No hay sesiones grabadas.")
                        .foregroundColor(.secondary)
                }
                ForEach(files, id: \.path) { file in
                    Button {
                        sharedFile = SharedFile(url: file)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.lastPathComponent)
                                    .font(.system(.subheadline, design: .monospaced))
                                Text(sizeText(file))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Sesiones")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            files = SessionRecorder.savedFiles()
        }
        .sheet(item: $sharedFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    private func sizeText(_ file: URL) -> String {
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? FileManager.default.removeItem(at: files[index])
        }
        files = SessionRecorder.savedFiles()
    }
}
