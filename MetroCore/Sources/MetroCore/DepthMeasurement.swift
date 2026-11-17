import Foundation

/// Medición de la profundidad de una estación con el barómetro: se empieza
/// en la boca y se acaba en el andén. Produce una fila para `tools/depths.csv`.
public struct DepthMeasurement: Codable, Equatable, Sendable {
    /// Altura aproximada del andén sobre el carril, en metros.
    public static let platformAboveRail = 1.05

    public static let csvHeader = "stop_id,nombre,cota_carril_m,desnivel_medido_m,cota_boca_m,metodo,fecha"

    public var stopID: String
    public var nombre: String
    /// Metros bajados de la boca al andén (positivo hacia abajo).
    public var desnivel: Double
    /// Cota del suelo en la boca donde empezó la medición, si se conoce.
    public var cotaBoca: Double?
    /// Fecha en formato `aaaa-mm-dd`.
    public var fecha: String

    public init(stopID: String, nombre: String, desnivel: Double, cotaBoca: Double?, fecha: String) {
        self.stopID = stopID
        self.nombre = nombre
        self.desnivel = desnivel
        self.cotaBoca = cotaBoca
        self.fecha = fecha
    }

    /// Cota del carril: la de la boca, menos lo bajado, menos la altura del andén.
    public var cotaCarril: Double? {
        cotaBoca.map { $0 - desnivel - DepthMeasurement.platformAboveRail }
    }

    public var csvRow: String {
        [
            DepthMeasurement.escape(stopID),
            DepthMeasurement.escape(nombre),
            cotaCarril.map { DepthMeasurement.number($0) } ?? "",
            DepthMeasurement.number(desnivel),
            cotaBoca.map { DepthMeasurement.number($0) } ?? "",
            "medido",
            fecha
        ].joined(separator: ",")
    }

    static func number(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Fecha de hoy en el formato del CSV.
    public static func today(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
