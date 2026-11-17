import Foundation

/// Una muestra de una sesión grabada: una lectura de GPS con la pose AR del
/// mismo instante. Los campos que no se conocen van a `nil`.
public struct SessionSample: Codable, Equatable, Sendable {
    /// Segundos desde el principio de la grabación.
    public var t: Double
    public var lat: Double?
    public var lon: Double?
    /// Precisión horizontal del GPS en metros.
    public var accuracy: Double?
    public var heading: Double?
    public var headingAccuracy: Double?
    /// Posición del móvil en el mundo de ARKit, en metros.
    public var arX: Double?
    public var arY: Double?
    public var arZ: Double?
    /// Altura del suelo detectado en el mundo de ARKit.
    public var groundY: Double?
    /// Estado del seguimiento de ARKit: "normal", "limitado" o "no disponible".
    public var tracking: String?

    public init(t: Double) {
        self.t = t
    }
}

/// Grabación de GPS + poses AR para reproducir una prueba de calle en un test.
public struct SessionRecording: Codable, Equatable, Sendable {
    public var version = 1
    public var inicio: String
    public var dispositivo: String
    /// Modo de seguimiento: "A" (geotracking) o "B" (manual).
    public var modo: String
    /// Origen geográfico de la escena durante la sesión.
    public var origenLat: Double
    public var origenLon: Double
    public var muestras: [SessionSample]

    public init(
        inicio: String,
        dispositivo: String,
        modo: String,
        origenLat: Double,
        origenLon: Double,
        muestras: [SessionSample] = []
    ) {
        self.inicio = inicio
        self.dispositivo = dispositivo
        self.modo = modo
        self.origenLat = origenLat
        self.origenLon = origenLon
        self.muestras = muestras
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SessionRecording {
        try JSONDecoder().decode(SessionRecording.self, from: data)
    }
}

public enum SessionReplay {
    /// Vuelve a pasar una grabación por el ajuste GPS-AR, como si se
    /// estuviera andando otra vez. Devuelve el estimador al final.
    public static func run(
        _ recording: SessionRecording,
        config: AlignmentEstimator.Config = AlignmentEstimator.Config()
    ) -> AlignmentEstimator {
        let frame = LocalFrame(origin: GeoPoint(latitude: recording.origenLat, longitude: recording.origenLon))
        var estimator = AlignmentEstimator(config: config)
        for sample in recording.muestras {
            guard let x = sample.arX, let z = sample.arZ else {
                continue
            }
            let ar = Vec2(x: x, z: z)
            if let lat = sample.lat, let lon = sample.lon, let accuracy = sample.accuracy {
                estimator.addGPS(geo: frame.plane(lon: lon, lat: lat), ar: ar, accuracy: accuracy)
            } else {
                estimator.track(ar: ar)
            }
        }
        return estimator
    }
}
