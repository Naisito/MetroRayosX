import CoreGraphics
import MetroCore
import RealityKit
import simd

/// Algo de la escena que lleva un rótulo: una estación, una boca o la línea
/// de profundidad. `local` va en coordenadas de la escena.
struct LabelItem {
    enum Kind {
        case station
        case boca
        case depth
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    /// `true` si el dato que enseña es una estimación.
    let estimated: Bool
    let local: SIMD3<Float>
}

/// Un rótulo ya colocado en la pantalla.
struct SceneLabel: Identifiable, Equatable {
    let id: String
    let kind: LabelItem.Kind
    let title: String
    let detail: String
    let estimated: Bool
    let point: CGPoint
    /// Metros desde la cámara.
    let distance: Float
}

/// Proyecta los rótulos a la pantalla. Se dibujan en SwiftUI por encima de
/// la vista AR, así que siempre miran a la cámara y se leen bien.
@MainActor
enum LabelProjector {
    static let maxLabels = 8

    static func project(
        _ items: [LabelItem],
        root: Entity,
        arView: ARView,
        camera: simd_float4x4
    ) -> [SceneLabel] {
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return []
        }
        let toCamera = camera.inverse
        var candidates: [SceneLabel] = []

        for item in items {
            let world = root.convert(position: item.local, to: nil)
            let inCamera = toCamera * simd_float4(world.x, world.y, world.z, 1)
            // La cámara mira hacia −z: lo que queda detrás no se rotula.
            guard inCamera.z < -0.5 else {
                continue
            }
            guard let point = arView.project(world),
                  point.x > 40, point.x < bounds.width - 40,
                  point.y > 70, point.y < bounds.height - 130
            else {
                continue
            }
            let distance = simd_length(simd_float3(inCamera.x, inCamera.y, inCamera.z))
            let detail: String
            switch item.kind {
            case .station:
                detail = "a \(GeoFormat.meters(Double(distance))) · \(item.detail)"
            case .boca, .depth:
                detail = item.detail
            }
            candidates.append(
                SceneLabel(
                    id: item.id,
                    kind: item.kind,
                    title: item.title,
                    detail: detail,
                    estimated: item.estimated,
                    point: point,
                    distance: distance
                )
            )
        }

        // Primero la profundidad, luego lo más cercano; los que se pisan se quitan.
        candidates.sort { a, b in
            if (a.kind == .depth) != (b.kind == .depth) {
                return a.kind == .depth
            }
            return a.distance < b.distance
        }
        var placed: [SceneLabel] = []
        for candidate in candidates {
            let overlaps = placed.contains { other in
                abs(other.point.x - candidate.point.x) < 170 && abs(other.point.y - candidate.point.y) < 46
            }
            if !overlaps {
                placed.append(candidate)
            }
            if placed.count >= maxLabels {
                break
            }
        }
        return placed
    }
}
