import Foundation
import simd
import UIKit
import ARKit

public struct Transform {
    public init(
        scale: SIMD3<Float> = .one,
        rotation: simd_quatf = simd_quatf(angle: 0, axis: .zero),
        translation: SIMD3<Float> = .zero
    ) {}
}

public protocol Material {}

public struct PhysicallyBasedMaterial: Material {
    public struct Texture {}
    public struct Opacity: ExpressibleByFloatLiteral {
        public init(scale: Float = 1.0, texture: Texture? = nil) {}
        public init(floatLiteral value: Float) {}
    }
    public enum Blending {
        case opaque
        case transparent(opacity: Opacity)
    }
}

public struct UnlitMaterial: Material {
    public typealias Blending = PhysicallyBasedMaterial.Blending
    public init(color: UIColor = .white, applyPostProcessToneMap: Bool = true) {}
    public var blending: Blending = .opaque
}

public struct MeshBuffer<Element> {
    public init(_ array: [Element]) {}
}

public struct MeshBuffers {
    public typealias Positions = MeshBuffer<SIMD3<Float>>
}

public struct MeshDescriptor {
    public enum Primitives {
        case triangles([UInt32])
        case polygons([UInt8], [UInt32])
    }
    public init(name: String = "") {}
    public var positions: MeshBuffers.Positions = MeshBuffers.Positions([])
    public var primitives: Primitives?
}

public class MeshResource {
    @MainActor @preconcurrency
    public static func generate(from descriptors: [MeshDescriptor]) throws -> MeshResource { MeshResource() }
    @MainActor @preconcurrency
    public static func generateBox(
        width: Float, height: Float, depth: Float, cornerRadius: Float = 0, splitFaces: Bool = false
    ) -> MeshResource { MeshResource() }
}

public struct ModelComponent {
    public var materials: [Material] = []
}

@MainActor @preconcurrency
open class Entity {
    public struct ChildCollection: Collection {
        var items: [Entity] = []
        public var startIndex: Int { 0 }
        public var endIndex: Int { items.count }
        public func index(after i: Int) -> Int { i + 1 }
        public subscript(i: Int) -> Entity { items[i] }
    }
    public init() {}
    public var name: String = ""
    public var isEnabled: Bool = true
    public var children: ChildCollection = ChildCollection()
    public var transform: Transform = Transform()
    public var position: SIMD3<Float> = .zero
    public var orientation: simd_quatf = simd_quatf(angle: 0, axis: .zero)
    public func addChild(_ child: Entity, preservingWorldTransform: Bool = false) {}
    public func removeFromParent(preservingWorldTransform: Bool = false) {}
    public func convert(position: SIMD3<Float>, to referenceEntity: Entity?) -> SIMD3<Float> { position }
}

open class ModelEntity: Entity {
    public var model: ModelComponent?
    public init(mesh: MeshResource, materials: [Material] = []) {}
}

open class AnchorEntity: Entity {
    public init(world position: SIMD3<Float>) {}
    public init(world transform: float4x4) {}
}

@MainActor @preconcurrency
public final class Scene {
    public func addAnchor(_ anchor: AnchorEntity) {}
}

@MainActor @preconcurrency
open class ARView: UIView {
    public enum CameraMode { case ar, nonAR }
    public struct RenderOptions: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let disablePersonOcclusion = RenderOptions(rawValue: 1)
        public static let disableDepthOfField = RenderOptions(rawValue: 2)
        public static let disableMotionBlur = RenderOptions(rawValue: 4)
        public static let disableHDR = RenderOptions(rawValue: 8)
        public static let disableCameraGrain = RenderOptions(rawValue: 16)
        public static let disableGroundingShadows = RenderOptions(rawValue: 32)
        public static let disableFaceMesh = RenderOptions(rawValue: 64)
        public static let disableAREnvironmentLighting = RenderOptions(rawValue: 128)
    }
    public init(frame: CGRect, cameraMode: CameraMode, automaticallyConfigureSession: Bool) {}
    public var renderOptions: RenderOptions = []
    public let scene = Scene()
    public let session = ARSession()
    public func project(_ point: SIMD3<Float>) -> CGPoint? { nil }
    public func ray(through screenPoint: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? { nil }
}
