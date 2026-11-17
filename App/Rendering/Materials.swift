import MetroCore
import RealityKit
import UIKit

/// Materiales sin iluminación: se ven siempre con su color, encima de la
/// imagen de la cámara. Es lo que da el efecto de rayos X.
@MainActor
enum Materials {
    static func unlit(_ color: UIColor, alpha: CGFloat = 1) -> RealityKit.Material {
        var material = UnlitMaterial(color: color.withAlphaComponent(alpha))
        if alpha < 0.999 {
            material.blending = .transparent(opacity: .init(scale: Float(alpha)))
        }
        return material
    }

    /// Color de una línea preparado para verse sobre la cámara (el negro de
    /// la L2 se aclara).
    static func lineColor(hex: String) -> UIColor {
        let rgb = ColorHex.displayRGB(hex)
        return UIColor(red: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), alpha: 1)
    }

    /// Mezcla un color con blanco (`amount` = 1 es blanco puro).
    static func lighten(_ color: UIColor, amount: CGFloat) -> UIColor {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(
            red: r + (1 - r) * amount,
            green: g + (1 - g) * amount,
            blue: b + (1 - b) * amount,
            alpha: a
        )
    }

    static let grid = UIColor(red: 0.75, green: 0.95, blue: 1.0, alpha: 1)
    static let window = UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1)
    static let depthLine = UIColor(red: 1.0, green: 0.92, blue: 0.25, alpha: 1)
    static let station = UIColor.white
    static let boca = UIColor(red: 0.6, green: 1.0, blue: 0.6, alpha: 1)
}

/// De la geometría de MetroCore a mallas de RealityKit.
@MainActor
enum MeshFactory {
    static func resource(_ mesh: MeshData, name: String) -> MeshResource? {
        guard !mesh.isEmpty else {
            return nil
        }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(mesh.positions)
        descriptor.primitives = .triangles(mesh.indices)
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            AppLog.shared.write("No se pudo crear la malla \(name): \(error)", category: "escena")
            return nil
        }
    }

    static func entity(_ mesh: MeshData, material: RealityKit.Material, name: String) -> ModelEntity? {
        guard let resource = resource(mesh, name: name) else {
            return nil
        }
        let entity = ModelEntity(mesh: resource, materials: [material])
        entity.name = name
        return entity
    }
}
