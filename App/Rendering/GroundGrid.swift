import MetroCore
import RealityKit
import UIKit

/// Rejilla del suelo alrededor del usuario, que se desvanece con la
/// distancia, y la «ventana» circular bajo sus pies.
@MainActor
final class GroundGrid {
    static let radius: Float = 30
    static let spacing: Float = 2.5
    static let windowRadius: Float = 2.5
    /// Opacidad de cada banda, de la más cercana a la más lejana.
    static let bandAlpha: [CGFloat] = [0.55, 0.32, 0.14]

    let node = Entity()

    private let lines = Entity()
    private var window: ModelEntity?
    private var lastCenter: Vec2?
    private var lastHeight: Float?

    init() {
        node.name = "rejilla"
        node.addChild(lines)

        var ring = MeshData()
        ring.addAnnulus(
            center: Vec3(0, 0, 0),
            inner: GroundGrid.windowRadius,
            outer: GroundGrid.windowRadius + 0.14,
            segments: 64
        )
        if let entity = MeshFactory.entity(ring, material: Materials.unlit(Materials.window, alpha: 0.9), name: "ventana") {
            window = entity
            node.addChild(entity)
        }
    }

    var entityCount: Int {
        lines.children.count + (window == nil ? 0 : 1)
    }

    func reset() {
        for child in Array(lines.children) {
            child.removeFromParent()
        }
        lastCenter = nil
        lastHeight = nil
    }

    /// `user` y `height` van en coordenadas de la escena. La ventana sigue al
    /// usuario; las líneas se regeneran cuando se ha movido un metro.
    func update(user: Vec2, height: Float) {
        window?.position = SIMD3<Float>(Float(user.x), height + 0.02, Float(user.z))

        if let center = lastCenter, let last = lastHeight,
           center.distance(to: user) < 1, abs(last - height) < 0.25 {
            return
        }
        lastCenter = user
        lastHeight = height

        for child in Array(lines.children) {
            child.removeFromParent()
        }
        let bands = TunnelMesher.groundGrid(
            userX: Float(user.x),
            userZ: Float(user.z),
            y: height,
            radius: GroundGrid.radius,
            spacing: GroundGrid.spacing,
            hole: GroundGrid.windowRadius,
            bands: GroundGrid.bandAlpha.count
        )
        for (index, band) in bands.enumerated() {
            let material = Materials.unlit(Materials.grid, alpha: GroundGrid.bandAlpha[index])
            if let entity = MeshFactory.entity(band, material: material, name: "rejilla-\(index)") {
                lines.addChild(entity)
            }
        }
    }
}
