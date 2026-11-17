import Foundation

/// Sistema de coordenadas de la escena: metros alrededor de un origen
/// geográfico, x = este, y = arriba, z = sur. La altura 0 es la cota
/// `cotaRef` (la del suelo en el origen).
public struct SceneFrame: Equatable, Sendable {
    public let frame: LocalFrame
    public let cotaRef: Double

    public init(origin: GeoPoint, cotaRef: Double) {
        frame = LocalFrame(origin: origin)
        self.cotaRef = cotaRef
    }

    public var origin: GeoPoint {
        frame.origin
    }

    public func position(lon: Double, lat: Double, cota: Double) -> Vec3 {
        let plane = frame.plane(lon: lon, lat: lat)
        return Vec3(Float(plane.x), Float(cota - cotaRef), Float(plane.z))
    }

    /// Posición del carril en un punto de vía.
    public func rail(_ punto: PuntoVia) -> Vec3 {
        position(lon: punto.lon, lat: punto.lat, cota: punto.cotaCarril)
    }

    /// Posición del suelo sobre un punto de vía.
    public func ground(_ punto: PuntoVia) -> Vec3 {
        position(lon: punto.lon, lat: punto.lat, cota: punto.cotaSuelo)
    }

    public func plane(_ point: GeoPoint) -> Vec2 {
        frame.plane(point)
    }

    public func geo(_ plane: Vec2) -> GeoPoint {
        frame.geo(plane)
    }

    /// Altura en la escena de una cota absoluta.
    public func height(ofCota cota: Double) -> Float {
        Float(cota - cotaRef)
    }

    /// Vector unitario horizontal para un rumbo en grados (0 = norte = −z).
    public static func direction(bearing: Double) -> Vec3 {
        let radians = bearing * .pi / 180
        return Vec3(Float(sin(radians)), 0, Float(-cos(radians)))
    }
}

/// Colores `#rrggbb`.
public enum ColorHex {
    /// Componentes de 0 a 1, o `nil` si el texto no es un color.
    public static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            return nil
        }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// Color para dibujar sobre la cámara: los colores oscuros (la L2 es
    /// negra) se aclaran hasta una luminancia mínima para que se vean.
    public static func displayRGB(_ hex: String, minLuminance: Double = 0.45) -> (r: Double, g: Double, b: Double) {
        let base = rgb(hex) ?? (1.0, 0.48, 0.0)
        let luminance = 0.2126 * base.r + 0.7152 * base.g + 0.0722 * base.b
        guard luminance < minLuminance else {
            return base
        }
        // Mezcla con blanco hasta alcanzar la luminancia mínima.
        let mix = (minLuminance - luminance) / max(1 - luminance, 1e-6)
        return (
            base.r + (1 - base.r) * mix,
            base.g + (1 - base.g) * mix,
            base.b + (1 - base.b) * mix
        )
    }
}

public enum SceneFade {
    /// Opacidad según la distancia: completa hasta `near` y bajando de forma
    /// lineal hasta `minAlpha` en `far`.
    public static func alpha(distance: Double, near: Double = 150, far: Double = 400, minAlpha: Double = 0.12) -> Double {
        if distance <= near {
            return 1
        }
        if distance >= far {
            return minAlpha
        }
        let f = (distance - near) / (far - near)
        return 1 - (1 - minAlpha) * f
    }

    /// Banda de opacidad (0 = la más cercana) para agrupar tramos por material.
    public static func band(distance: Double, bands: Int = 4, near: Double = 150, far: Double = 400) -> Int {
        let count = max(bands, 1)
        if distance <= near {
            return 0
        }
        if distance >= far {
            return count - 1
        }
        let f = (distance - near) / (far - near)
        return min(Int(f * Double(count - 1)) + 1, count - 1)
    }

    /// Opacidad representativa de una banda.
    public static func alpha(band: Int, bands: Int = 4, minAlpha: Double = 0.12) -> Double {
        let count = max(bands, 1)
        guard count > 1 else {
            return 1
        }
        let f = Double(min(max(band, 0), count - 1)) / Double(count - 1)
        return 1 - (1 - minAlpha) * f
    }
}
