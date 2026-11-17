import SwiftUI

@main
struct MetroRayosXApp: App {
    @StateObject private var location = LocationService()
    @StateObject private var store = NetworkStore()
    @StateObject private var realtime = RealtimeService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppLog.shared.logSessionStart()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(location)
                .environmentObject(store)
                .environmentObject(realtime)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                AppLog.shared.write("App en primer plano")
            case .inactive:
                AppLog.shared.write("App inactiva")
            case .background:
                AppLog.shared.write("App en segundo plano")
            @unknown default:
                AppLog.shared.write("Estado de la app desconocido")
            }
        }
    }
}

/// Pestañas de la app y pantalla de bienvenida.
struct RootView: View {
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var store: NetworkStore
    @AppStorage("bienvenidaVista") private var welcomed = false

    var body: some View {
        TabView {
            MapScreen()
                .tabItem {
                    Label("Mapa", systemImage: "map")
                }
            ARScreen()
                .tabItem {
                    Label("Rayos X", systemImage: "viewfinder")
                }
            MeasureScreen()
                .tabItem {
                    Label("Medir", systemImage: "barometer")
                }
            MoreScreen()
                .tabItem {
                    Label("Más", systemImage: "ellipsis.circle")
                }
        }
        .onAppear {
            store.load()
        }
        .sheet(isPresented: showWelcome) {
            OnboardingScreen {
                welcomed = true
                // El permiso de ubicación se pide al cerrar la bienvenida.
                location.start()
            }
        }
    }

    private var showWelcome: Binding<Bool> {
        Binding(
            get: { !welcomed },
            set: { presented in
                if !presented {
                    welcomed = true
                }
            }
        )
    }
}
