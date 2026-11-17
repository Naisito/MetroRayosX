import SwiftUI

@main
struct MetroRayosXApp: App {
    @StateObject private var location = LocationService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppLog.shared.logSessionStart()
    }

    var body: some Scene {
        WindowGroup {
            StatusScreen()
                .environmentObject(location)
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
