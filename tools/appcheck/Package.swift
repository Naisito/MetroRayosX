// swift-tools-version:5.9
import PackageDescription

// Arnes de comprobacion: compila en Linux los fuentes de la app contra
// modulos de pega con los nombres de los frameworks de Apple.
let package = Package(
    name: "chk",
    dependencies: [.package(path: "../MetroCore")],
    targets: [
        .target(name: "simd", path: "Stubs/simd"),
        .target(name: "CoreGraphics", path: "Stubs/CoreGraphics"),
        .target(name: "Combine", path: "Stubs/Combine"),
        .target(name: "UIKit", path: "Stubs/UIKit"),
        .target(name: "CoreLocation", path: "Stubs/CoreLocation"),
        .target(name: "CoreMotion", path: "Stubs/CoreMotion"),
        .target(name: "ARKit", dependencies: ["simd", "CoreLocation", "UIKit"], path: "Stubs/ARKit"),
        .target(name: "RealityKit", dependencies: ["simd", "UIKit", "ARKit"], path: "Stubs/RealityKit"),
        .target(name: "MapKit", dependencies: ["CoreLocation", "UIKit"], path: "Stubs/MapKit"),
        .target(name: "SwiftUI", dependencies: ["Combine", "UIKit"], path: "Stubs/SwiftUI"),
        .target(name: "AppCheck", dependencies: [
            "simd", "CoreGraphics", "Combine", "UIKit", "CoreLocation", "CoreMotion", "ARKit", "RealityKit",
            "MapKit", "SwiftUI",
            .product(name: "MetroCore", package: "MetroCore")
        ], path: "AppSrc")
    ]
)
