import Foundation

// Modelo de `metro.json`, generado por `tools/build_network.py`.
// Las cotas son metros sobre el nivel del mar.

public struct Linea: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let nombre: String
    /// Color en formato `#rrggbb`.
    public let color: String

    public init(id: String, nombre: String, color: String) {
        self.id = id
        self.nombre = nombre
        self.color = color
    }
}

/// Punto de una vía. En el JSON es `[lon, lat, cotaCarril, cotaSuelo]`.
public struct PuntoVia: Codable, Equatable, Sendable {
    public let lon: Double
    public let lat: Double
    public let cotaCarril: Double
    public let cotaSuelo: Double

    public init(lon: Double, lat: Double, cotaCarril: Double, cotaSuelo: Double) {
        self.lon = lon
        self.lat = lat
        self.cotaCarril = cotaCarril
        self.cotaSuelo = cotaSuelo
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        lon = try container.decode(Double.self)
        lat = try container.decode(Double.self)
        cotaCarril = try container.decode(Double.self)
        cotaSuelo = try container.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(lon)
        try container.encode(lat)
        try container.encode(cotaCarril)
        try container.encode(cotaSuelo)
    }

    public var geo: GeoPoint {
        GeoPoint(latitude: lat, longitude: lon)
    }

    /// Metros entre el suelo y el carril en este punto.
    public var profundidad: Double {
        cotaSuelo - cotaCarril
    }

    /// Punto intermedio entre este y `other` (t = 0 es este, t = 1 es `other`).
    public func interpolated(to other: PuntoVia, t: Double) -> PuntoVia {
        PuntoVia(
            lon: lon + (other.lon - lon) * t,
            lat: lat + (other.lat - lat) * t,
            cotaCarril: cotaCarril + (other.cotaCarril - cotaCarril) * t,
            cotaSuelo: cotaSuelo + (other.cotaSuelo - cotaSuelo) * t
        )
    }
}

/// Un tramo de vía (un `way` de OSM) remuestreado cada 5 m como mucho.
public struct Via: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let lineas: [String]
    public let tunel: Bool
    /// Número de vías que representa el tramo (`tracks` en OSM).
    public let pistas: Int
    public let puntos: [PuntoVia]

    public init(id: String, lineas: [String], tunel: Bool, pistas: Int = 1, puntos: [PuntoVia]) {
        self.id = id
        self.lineas = lineas
        self.tunel = tunel
        self.pistas = pistas
        self.puntos = puntos
    }

    private enum CodingKeys: String, CodingKey {
        case id, lineas, tunel, pistas, puntos
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        lineas = try container.decodeIfPresent([String].self, forKey: .lineas) ?? []
        tunel = try container.decodeIfPresent(Bool.self, forKey: .tunel) ?? false
        pistas = max(try container.decodeIfPresent(Int.self, forKey: .pistas) ?? 1, 1)
        puntos = try container.decode([PuntoVia].self, forKey: .puntos)
    }
}

public struct TramoRuta: Codable, Equatable, Sendable {
    public let via: String
    /// `true` si la vía se recorre al revés de como están guardados sus puntos.
    public let inv: Bool

    public init(via: String, inv: Bool) {
        self.via = via
        self.inv = inv
    }
}

/// Recorrido de una línea en un sentido, de terminal a terminal.
public struct Ruta: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let linea: String
    public let nombre: String
    public let tramos: [TramoRuta]

    public init(id: String, linea: String, nombre: String, tramos: [TramoRuta]) {
        self.id = id
        self.linea = linea
        self.nombre = nombre
        self.tramos = tramos
    }

    private enum CodingKeys: String, CodingKey {
        case id, linea, nombre, tramos
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        linea = try container.decode(String.self, forKey: .linea)
        nombre = try container.decodeIfPresent(String.self, forKey: .nombre) ?? ""
        tramos = try container.decode([TramoRuta].self, forKey: .tramos)
    }
}

public struct Boca: Codable, Equatable, Sendable {
    public let nombre: String
    public let lat: Double
    public let lon: Double
    public let cotaSuelo: Double

    public init(nombre: String, lat: Double, lon: Double, cotaSuelo: Double) {
        self.nombre = nombre
        self.lat = lat
        self.lon = lon
        self.cotaSuelo = cotaSuelo
    }

    private enum CodingKeys: String, CodingKey {
        case nombre, lat, lon, cotaSuelo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nombre = try container.decodeIfPresent(String.self, forKey: .nombre) ?? ""
        lat = try container.decode(Double.self, forKey: .lat)
        lon = try container.decode(Double.self, forKey: .lon)
        cotaSuelo = try container.decodeIfPresent(Double.self, forKey: .cotaSuelo) ?? 0
    }

    public var geo: GeoPoint {
        GeoPoint(latitude: lat, longitude: lon)
    }
}

/// De dónde sale la cota del carril de una estación.
public enum OrigenCota: String, Codable, Equatable, Sendable {
    case medido
    case proyecto
    case estimado

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OrigenCota(rawValue: raw.trimmingCharacters(in: .whitespaces)) ?? .estimado
    }
}

public struct Estacion: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let nombre: String
    public let lat: Double
    public let lon: Double
    public let cotaCarril: Double
    public let cotaSuelo: Double
    public let subterranea: Bool
    public let origenCota: OrigenCota
    public let lineas: [String]
    /// Todos los `stop_id` del GTFS que pertenecen a la estación.
    public let paradas: [String]
    public let bocas: [Boca]

    public init(
        id: String,
        nombre: String,
        lat: Double,
        lon: Double,
        cotaCarril: Double,
        cotaSuelo: Double,
        subterranea: Bool,
        origenCota: OrigenCota = .estimado,
        lineas: [String] = [],
        paradas: [String] = [],
        bocas: [Boca] = []
    ) {
        self.id = id
        self.nombre = nombre
        self.lat = lat
        self.lon = lon
        self.cotaCarril = cotaCarril
        self.cotaSuelo = cotaSuelo
        self.subterranea = subterranea
        self.origenCota = origenCota
        self.lineas = lineas
        self.paradas = paradas
        self.bocas = bocas
    }

    private enum CodingKeys: String, CodingKey {
        case id, nombre, lat, lon, cotaCarril, cotaSuelo, subterranea, origenCota, lineas, paradas, bocas
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        nombre = try container.decode(String.self, forKey: .nombre)
        lat = try container.decode(Double.self, forKey: .lat)
        lon = try container.decode(Double.self, forKey: .lon)
        cotaCarril = try container.decode(Double.self, forKey: .cotaCarril)
        cotaSuelo = try container.decode(Double.self, forKey: .cotaSuelo)
        subterranea = try container.decodeIfPresent(Bool.self, forKey: .subterranea) ?? true
        origenCota = try container.decodeIfPresent(OrigenCota.self, forKey: .origenCota) ?? .estimado
        lineas = try container.decodeIfPresent([String].self, forKey: .lineas) ?? []
        paradas = try container.decodeIfPresent([String].self, forKey: .paradas) ?? []
        bocas = try container.decodeIfPresent([Boca].self, forKey: .bocas) ?? []
    }

    public var geo: GeoPoint {
        GeoPoint(latitude: lat, longitude: lon)
    }

    /// Metros entre el suelo sobre la estación y el carril.
    public var profundidad: Double {
        cotaSuelo - cotaCarril
    }
}

/// Descripción de la rejilla de `relieve.bin`.
public struct RelieveInfo: Codable, Equatable, Sendable {
    /// Paso aproximado en metros (informativo).
    public let pasoM: Double
    /// `[lon, lat]` de la celda (fila 0, columna 0), la más al suroeste.
    public let origen: [Double]
    public let pasoLon: Double
    public let pasoLat: Double
    public let filas: Int
    public let columnas: Int
    public let sinDato: Int
    public let fichero: String

    public init(
        pasoM: Double,
        origen: [Double],
        pasoLon: Double,
        pasoLat: Double,
        filas: Int,
        columnas: Int,
        sinDato: Int = -32768,
        fichero: String = "relieve.bin"
    ) {
        self.pasoM = pasoM
        self.origen = origen
        self.pasoLon = pasoLon
        self.pasoLat = pasoLat
        self.filas = filas
        self.columnas = columnas
        self.sinDato = sinDato
        self.fichero = fichero
    }

    private enum CodingKeys: String, CodingKey {
        case pasoM = "paso_m"
        case origen
        case pasoLon = "paso_lon"
        case pasoLat = "paso_lat"
        case filas, columnas
        case sinDato = "sin_dato"
        case fichero
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pasoM = try container.decodeIfPresent(Double.self, forKey: .pasoM) ?? 10
        origen = try container.decode([Double].self, forKey: .origen)
        pasoLon = try container.decode(Double.self, forKey: .pasoLon)
        pasoLat = try container.decode(Double.self, forKey: .pasoLat)
        filas = try container.decode(Int.self, forKey: .filas)
        columnas = try container.decode(Int.self, forKey: .columnas)
        sinDato = try container.decodeIfPresent(Int.self, forKey: .sinDato) ?? -32768
        fichero = try container.decodeIfPresent(String.self, forKey: .fichero) ?? "relieve.bin"
    }
}

/// La red completa.
public struct Red: Codable, Equatable, Sendable {
    public let version: Int
    public let generado: String
    public let atribucion: [String]
    public let lineas: [Linea]
    public let vias: [Via]
    public let rutas: [Ruta]
    public let estaciones: [Estacion]
    public let relieve: RelieveInfo?

    public init(
        version: Int = 1,
        generado: String = "",
        atribucion: [String] = [],
        lineas: [Linea],
        vias: [Via],
        rutas: [Ruta] = [],
        estaciones: [Estacion],
        relieve: RelieveInfo? = nil
    ) {
        self.version = version
        self.generado = generado
        self.atribucion = atribucion
        self.lineas = lineas
        self.vias = vias
        self.rutas = rutas
        self.estaciones = estaciones
        self.relieve = relieve
    }

    private enum CodingKeys: String, CodingKey {
        case version, generado, atribucion, lineas, vias, rutas, estaciones, relieve
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        generado = try container.decodeIfPresent(String.self, forKey: .generado) ?? ""
        atribucion = try container.decodeIfPresent([String].self, forKey: .atribucion) ?? []
        lineas = try container.decodeIfPresent([Linea].self, forKey: .lineas) ?? []
        vias = try container.decode([Via].self, forKey: .vias)
        rutas = try container.decodeIfPresent([Ruta].self, forKey: .rutas) ?? []
        estaciones = try container.decodeIfPresent([Estacion].self, forKey: .estaciones) ?? []
        relieve = try container.decodeIfPresent(RelieveInfo.self, forKey: .relieve)
    }

    public func linea(_ id: String) -> Linea? {
        lineas.first { $0.id == id }
    }
}
