import Foundation

// Geometría de la escena: de polilíneas a vértices e índices.
// Coordenadas de escena en metros: x = este, y = arriba, z = sur.

public typealias Vec3 = SIMD3<Float>

func v3dot(_ a: Vec3, _ b: Vec3) -> Float {
    a.x * b.x + a.y * b.y + a.z * b.z
}

func v3cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
    Vec3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
}

func v3length(_ a: Vec3) -> Float {
    v3dot(a, a).squareRoot()
}

func v3normalize(_ a: Vec3, fallback: Vec3 = Vec3(1, 0, 0)) -> Vec3 {
    let l = v3length(a)
    return l > 1e-6 ? a / l : fallback
}

/// Perpendicular horizontal a una dirección: apunta a la derecha del sentido de avance.
func v3side(_ direction: Vec3) -> Vec3 {
    v3normalize(Vec3(-direction.z, 0, direction.x))
}

/// Triángulos listos para crear una malla. Todas las caras son de doble cara
/// (se emiten los dos sentidos) para no depender de la orientación.
public struct MeshData: Equatable, Sendable {
    public var positions: [Vec3] = []
    public var indices: [UInt32] = []

    public init() {}

    public var isEmpty: Bool {
        indices.isEmpty
    }

    public var triangleCount: Int {
        indices.count / 3
    }

    public mutating func append(_ other: MeshData) {
        let base = UInt32(positions.count)
        positions.append(contentsOf: other.positions)
        indices.append(contentsOf: other.indices.map { $0 + base })
    }

    /// Cuadrilátero con los vértices en orden de perímetro.
    public mutating func addQuad(_ a: Vec3, _ b: Vec3, _ c: Vec3, _ d: Vec3) {
        let base = UInt32(positions.count)
        positions.append(contentsOf: [a, b, c, d])
        addQuadIndices(base, base + 1, base + 2, base + 3)
    }

    private mutating func addQuadIndices(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) {
        indices.append(contentsOf: [a, b, c, a, c, d])
        indices.append(contentsOf: [a, c, b, a, d, c])
    }

    /// Cinta plana y horizontal que sigue una polilínea.
    /// `lateral` la desplaza a la derecha del avance y `lift` hacia arriba.
    public mutating func addRibbon(path: [Vec3], width: Float, lateral: Float = 0, lift: Float = 0) {
        guard path.count >= 2 else {
            return
        }
        let base = UInt32(positions.count)
        let half = width / 2
        for i in path.indices {
            let previous = path[max(i - 1, 0)]
            let next = path[min(i + 1, path.count - 1)]
            let side = v3side(v3normalize(next - previous))
            let center = path[i] + side * lateral + Vec3(0, lift, 0)
            positions.append(center - side * half)
            positions.append(center + side * half)
        }
        for i in 0..<(path.count - 1) {
            let a = base + UInt32(i * 2)
            addQuadIndices(a, a + 1, a + 3, a + 2)
        }
    }

    /// Barra de sección cuadrada entre dos puntos.
    public mutating func addBar(from a: Vec3, to b: Vec3, thickness: Float) {
        let direction = b - a
        guard v3length(direction) > 1e-5 else {
            return
        }
        let d = v3normalize(direction)
        // Con barras casi verticales la perpendicular horizontal no existe.
        let u = abs(d.y) > 0.99 ? Vec3(1, 0, 0) : v3side(d)
        let v = v3normalize(v3cross(d, u), fallback: Vec3(0, 1, 0))
        let h = thickness / 2
        let uh: Vec3 = u * h
        let vh: Vec3 = v * h
        let offsets: [Vec3] = [uh + vh, uh - vh, -uh - vh, vh - uh]
        for i in 0..<4 {
            let o1 = offsets[i]
            let o2 = offsets[(i + 1) % 4]
            addQuad(a + o1, b + o1, b + o2, a + o2)
        }
    }

    /// Anillo (banda circular) perpendicular a `tangent`.
    public mutating func addRing(center: Vec3, tangent: Vec3, radius: Float, segments: Int, width: Float) {
        let d = v3normalize(tangent, fallback: Vec3(0, 0, -1))
        let side = v3side(d)
        let up = v3normalize(v3cross(side, d), fallback: Vec3(0, 1, 0))
        let count = max(segments, 3)
        let base = UInt32(positions.count)
        let half = d * (width / 2)
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * Double.pi
            let c = Float(cos(angle)) * radius
            let s = Float(sin(angle)) * radius
            let radial: Vec3 = side * c + up * s
            let rim: Vec3 = center + radial
            positions.append(rim - half)
            positions.append(rim + half)
        }
        for i in 0..<count {
            let a = base + UInt32(i * 2)
            let b = base + UInt32(((i + 1) % count) * 2)
            addQuadIndices(a, a + 1, b + 1, b)
        }
    }

    /// Corona circular horizontal (la «ventana» bajo los pies).
    public mutating func addAnnulus(center: Vec3, inner: Float, outer: Float, segments: Int) {
        let count = max(segments, 3)
        let base = UInt32(positions.count)
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi
            let direction = Vec3(Float(cos(angle)), 0, Float(sin(angle)))
            positions.append(center + direction * inner)
            positions.append(center + direction * outer)
        }
        for i in 0..<count {
            let a = base + UInt32(i * 2)
            let b = base + UInt32(((i + 1) % count) * 2)
            addQuadIndices(a, a + 1, b + 1, b)
        }
    }

    /// Caja maciza orientada: `direction` es el eje largo (horizontal) y
    /// `center` el centro de la cara inferior.
    public mutating func addBox(center: Vec3, direction: Vec3, length: Float, width: Float, height: Float) {
        let corners = MeshData.boxCorners(
            center: center, direction: direction, length: length, width: width, height: height
        )
        // Abajo 0-3, arriba 4-7.
        addQuad(corners[0], corners[1], corners[2], corners[3])
        addQuad(corners[4], corners[5], corners[6], corners[7])
        for i in 0..<4 {
            let j = (i + 1) % 4
            addQuad(corners[i], corners[j], corners[j + 4], corners[i + 4])
        }
    }

    /// Las doce aristas de una caja, como barras.
    public mutating func addWireBox(
        center: Vec3,
        direction: Vec3,
        length: Float,
        width: Float,
        height: Float,
        thickness: Float
    ) {
        let corners = MeshData.boxCorners(
            center: center, direction: direction, length: length, width: width, height: height
        )
        for i in 0..<4 {
            let j = (i + 1) % 4
            addBar(from: corners[i], to: corners[j], thickness: thickness)
            addBar(from: corners[i + 4], to: corners[j + 4], thickness: thickness)
            addBar(from: corners[i], to: corners[i + 4], thickness: thickness)
        }
    }

    static func boxCorners(center: Vec3, direction: Vec3, length: Float, width: Float, height: Float) -> [Vec3] {
        let d = v3normalize(Vec3(direction.x, 0, direction.z), fallback: Vec3(0, 0, -1))
        let side = v3side(d)
        let l: Vec3 = d * (length / 2)
        let w: Vec3 = side * (width / 2)
        let back: Vec3 = center - l
        let front: Vec3 = center + l
        let lift = Vec3(0, height, 0)
        var corners: [Vec3] = [back - w, front - w, front + w, back + w]
        for i in 0..<4 {
            corners.append(corners[i] + lift)
        }
        return corners
    }
}

/// Medidas del dibujo del túnel, en metros.
public struct TunnelStyle: Sendable {
    /// Ancho de vía: el metro de Bilbao es de vía métrica.
    public var gauge: Float = 1.0
    /// Más anchos que un carril real para que se vean a distancia.
    public var railWidth: Float = 0.16
    public var bedWidth: Float = 2.6
    public var ringSpacing: Double = 10
    public var ringRadius: Float = 2.9
    public var ringSegments = 16
    public var ringWidth: Float = 0.35
    /// Altura del centro del anillo sobre el carril.
    public var ringLift: Float = 1.9
    /// Separación entre ejes cuando un tramo representa dos vías.
    public var trackSpacing: Float = 3.8
    public var wallLineWidth: Float = 0.14

    public init() {}
}

/// Mallas de un tramo de vía, separadas por material.
public struct TrackMesh: Equatable, Sendable {
    public var rails = MeshData()
    public var bed = MeshData()
    /// Anillos y líneas de pared. Vacía fuera de túnel.
    public var structure = MeshData()

    public init() {}
}

public enum TunnelMesher {
    /// Malla de un tramo de vía.
    /// - Parameters:
    ///   - path: puntos del carril en coordenadas de escena.
    ///   - startChainage: metros desde el principio de la vía hasta `path[0]`;
    ///     hace que los anillos caigan cada 10 m exactos aunque la vía se parta en tramos.
    public static func track(
        path: [Vec3],
        startChainage: Double,
        tunnel: Bool,
        tracks: Int,
        style: TunnelStyle = TunnelStyle()
    ) -> TrackMesh {
        var mesh = TrackMesh()
        guard path.count >= 2 else {
            return mesh
        }

        let count = max(tracks, 1)
        let offsets: [Float] = (0..<count).map { index in
            (Float(index) - Float(count - 1) / 2) * style.trackSpacing
        }

        for lateral in offsets {
            mesh.bed.addRibbon(path: path, width: style.bedWidth, lateral: lateral, lift: -0.05)
            mesh.rails.addRibbon(path: path, width: style.railWidth, lateral: lateral - style.gauge / 2, lift: 0.02)
            mesh.rails.addRibbon(path: path, width: style.railWidth, lateral: lateral + style.gauge / 2, lift: 0.02)
            if tunnel {
                let r = style.ringRadius
                mesh.structure.addRibbon(
                    path: path, width: style.wallLineWidth, lateral: lateral, lift: style.ringLift + r
                )
                mesh.structure.addRibbon(
                    path: path, width: style.wallLineWidth, lateral: lateral - r, lift: style.ringLift
                )
                mesh.structure.addRibbon(
                    path: path, width: style.wallLineWidth, lateral: lateral + r, lift: style.ringLift
                )
            }
        }

        if tunnel, style.ringSpacing > 0 {
            for ring in ringPositions(path: path, startChainage: startChainage, spacing: style.ringSpacing) {
                let side = v3side(ring.tangent)
                for lateral in offsets {
                    mesh.structure.addRing(
                        center: ring.point + side * lateral + Vec3(0, style.ringLift, 0),
                        tangent: ring.tangent,
                        radius: style.ringRadius,
                        segments: style.ringSegments,
                        width: style.ringWidth
                    )
                }
            }
        }
        return mesh
    }

    /// Puntos donde va un anillo: múltiplos de `spacing` en [inicio, fin) del tramo.
    static func ringPositions(
        path: [Vec3],
        startChainage: Double,
        spacing: Double
    ) -> [(point: Vec3, tangent: Vec3)] {
        var result: [(point: Vec3, tangent: Vec3)] = []
        var chainage = startChainage
        var next = (startChainage / spacing).rounded(.up) * spacing
        for i in 0..<(path.count - 1) {
            let a = path[i]
            let b = path[i + 1]
            let dx = Double(b.x - a.x)
            let dz = Double(b.z - a.z)
            let length = (dx * dx + dz * dz).squareRoot()
            guard length > 1e-6 else {
                continue
            }
            let end = chainage + length
            while next < end {
                let t = Float((next - chainage) / length)
                result.append((a + (b - a) * t, v3normalize(b - a)))
                next += spacing
            }
            chainage = end
        }
        return result
    }

    /// Rejilla del suelo alrededor del usuario, en bandas por distancia para
    /// poder desvanecerla. Las líneas caen en múltiplos de `spacing`, de modo
    /// que la rejilla se queda fija en el suelo aunque se regenere al andar.
    /// Dentro de `hole` no hay líneas: es la ventana bajo los pies.
    public static func groundGrid(
        userX: Float,
        userZ: Float,
        y: Float,
        radius: Float,
        spacing: Float,
        hole: Float,
        bands: Int = 3,
        lineWidth: Float = 0.04
    ) -> [MeshData] {
        let bandCount = max(bands, 1)
        var result = [MeshData](repeating: MeshData(), count: bandCount)
        guard spacing > 0, radius > hole else {
            return result
        }

        let minI = Int(((userX - radius) / spacing).rounded(.down))
        let maxI = Int(((userX + radius) / spacing).rounded(.up))
        let minK = Int(((userZ - radius) / spacing).rounded(.down))
        let maxK = Int(((userZ + radius) / spacing).rounded(.up))

        func band(forMidX x: Float, midZ z: Float) -> Int? {
            let dx = x - userX
            let dz = z - userZ
            let distance = (dx * dx + dz * dz).squareRoot()
            if distance < hole || distance > radius {
                return nil
            }
            return min(Int(distance / radius * Float(bandCount)), bandCount - 1)
        }

        for i in minI...maxI {
            let x = Float(i) * spacing
            for k in minK..<maxK {
                let z0 = Float(k) * spacing
                let z1 = z0 + spacing
                // Línea norte-sur.
                if let b = band(forMidX: x, midZ: (z0 + z1) / 2) {
                    let w = lineWidth * Float(b + 1) / 2
                    result[b].addQuad(
                        Vec3(x - w, y, z0), Vec3(x + w, y, z0), Vec3(x + w, y, z1), Vec3(x - w, y, z1)
                    )
                }
            }
        }
        for k in minK...maxK {
            let z = Float(k) * spacing
            for i in minI..<maxI {
                let x0 = Float(i) * spacing
                let x1 = x0 + spacing
                // Línea este-oeste.
                if let b = band(forMidX: (x0 + x1) / 2, midZ: z) {
                    let w = lineWidth * Float(b + 1) / 2
                    result[b].addQuad(
                        Vec3(x0, y, z - w), Vec3(x1, y, z - w), Vec3(x1, y, z + w), Vec3(x0, y, z + w)
                    )
                }
            }
        }
        return result
    }
}
