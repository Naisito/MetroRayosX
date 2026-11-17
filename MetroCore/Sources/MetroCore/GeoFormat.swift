import Foundation

/// Textos de coordenadas, distancias y rumbos para la interfaz.
public enum GeoFormat {
    /// Grados con seis decimales (unos 10 cm), con punto decimal para poder copiarlos.
    public static func degrees(_ value: Double) -> String {
        String(format: "%.6f°", value)
    }

    /// Distancia en metros, o en kilómetros con coma decimal a partir de 1 km.
    public static func meters(_ value: Double) -> String {
        if abs(value) < 1000 {
            return String(format: "%.0f m", value)
        }
        return String(format: "%.1f km", value / 1000).replacingOccurrences(of: ".", with: ",")
    }

    /// Punto cardinal en castellano para un rumbo en grados (0 = norte, 90 = este).
    public static func cardinal(_ heading: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        var normalized = heading.truncatingRemainder(dividingBy: 360)
        if normalized < 0 {
            normalized += 360
        }
        let index = Int((normalized + 22.5) / 45) % names.count
        return names[index]
    }
}
