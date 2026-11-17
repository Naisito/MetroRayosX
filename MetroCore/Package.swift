// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MetroCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "MetroCore", targets: ["MetroCore"])
    ],
    targets: [
        .target(name: "MetroCore"),
        // Los tests leen `Fixtures/` y `App/Resources/` por ruta, con #filePath.
        .testTarget(name: "MetroCoreTests", dependencies: ["MetroCore"], exclude: ["Fixtures"])
    ]
)
