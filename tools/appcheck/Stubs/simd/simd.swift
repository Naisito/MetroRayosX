public typealias simd_float3 = SIMD3<Float>
public typealias simd_float4 = SIMD4<Float>

public struct simd_float4x4 {
    public var columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    public init() { columns = (.zero, .zero, .zero, .zero) }
    public var inverse: simd_float4x4 { self }
    public static func * (m: simd_float4x4, v: SIMD4<Float>) -> SIMD4<Float> { v }
}

public typealias float4x4 = simd_float4x4

public struct simd_quatf {
    public init(angle: Float, axis: SIMD3<Float>) {}
}

public func simd_length(_ v: SIMD3<Float>) -> Float { 0 }
