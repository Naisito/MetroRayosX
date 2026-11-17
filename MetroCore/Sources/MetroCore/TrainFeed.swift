import Foundation

// Decodificador mínimo de GTFS-Realtime (protobuf), escrito a mano para no
// añadir dependencias a la app. Solo lee los campos que usa el proyecto;
// los demás se saltan.

public enum ProtoError: Error, Equatable {
    case truncated
    case malformedVarint
    case unsupportedWireType(Int)
}

/// Lector de mensajes protobuf sobre un bloque de bytes.
struct ProtoReader {
    private let bytes: [UInt8]
    private var position: Int
    private let end: Int

    init(_ data: Data) {
        bytes = [UInt8](data)
        position = 0
        end = bytes.count
    }

    private init(bytes: [UInt8], start: Int, end: Int) {
        self.bytes = bytes
        self.position = start
        self.end = end
    }

    var isAtEnd: Bool {
        position >= end
    }

    /// Siguiente campo: número y tipo de codificación. `nil` al acabar el mensaje.
    mutating func nextField() throws -> (number: Int, wireType: Int)? {
        guard !isAtEnd else {
            return nil
        }
        let key = try readVarint()
        return (Int(key >> 3), Int(key & 0x7))
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard position < end else {
                throw ProtoError.truncated
            }
            let byte = bytes[position]
            position += 1
            if shift >= 64 {
                throw ProtoError.malformedVarint
            }
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
    }

    mutating func readFixed32() throws -> UInt32 {
        guard position + 4 <= end else {
            throw ProtoError.truncated
        }
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(bytes[position + i]) << UInt32(8 * i)
        }
        position += 4
        return value
    }

    mutating func readFixed64() throws -> UInt64 {
        guard position + 8 <= end else {
            throw ProtoError.truncated
        }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(bytes[position + i]) << UInt64(8 * i)
        }
        position += 8
        return value
    }

    mutating func readFloat() throws -> Float {
        Float(bitPattern: try readFixed32())
    }

    /// Submensaje (o cadena o bytes) delimitado por longitud.
    mutating func readMessage() throws -> ProtoReader {
        let length = Int(truncatingIfNeeded: try readVarint())
        guard length >= 0, length <= end - position else {
            throw ProtoError.truncated
        }
        let reader = ProtoReader(bytes: bytes, start: position, end: position + length)
        position += length
        return reader
    }

    mutating func readString() throws -> String {
        let length = Int(truncatingIfNeeded: try readVarint())
        guard length >= 0, length <= end - position else {
            throw ProtoError.truncated
        }
        let text = String(decoding: bytes[position..<(position + length)], as: UTF8.self)
        position += length
        return text
    }

    mutating func skip(wireType: Int) throws {
        switch wireType {
        case 0:
            _ = try readVarint()
        case 1:
            _ = try readFixed64()
        case 2:
            _ = try readMessage()
        case 5:
            _ = try readFixed32()
        default:
            throw ProtoError.unsupportedWireType(wireType)
        }
    }
}

// MARK: - Modelo

public struct RTTrip: Equatable, Sendable {
    public var tripID: String?
    public var routeID: String?
    public var directionID: Int?
    public var startTime: String?
    public var startDate: String?

    public init(
        tripID: String? = nil,
        routeID: String? = nil,
        directionID: Int? = nil,
        startTime: String? = nil,
        startDate: String? = nil
    ) {
        self.tripID = tripID
        self.routeID = routeID
        self.directionID = directionID
        self.startTime = startTime
        self.startDate = startDate
    }
}

public struct RTVehicle: Equatable, Sendable {
    public var entityID: String
    public var trip: RTTrip
    public var vehicleID: String?
    public var label: String?
    public var latitude: Double?
    public var longitude: Double?
    public var bearing: Double?
    /// Metros por segundo.
    public var speed: Double?
    public var stopID: String?
    public var currentStopSequence: Int?
    /// 0 = llegando, 1 = parado, 2 = en camino.
    public var status: Int?
    public var timestamp: Date?

    public init(entityID: String = "", trip: RTTrip = RTTrip()) {
        self.entityID = entityID
        self.trip = trip
    }

    public var hasPosition: Bool {
        guard let latitude = latitude, let longitude = longitude else {
            return false
        }
        return abs(latitude) > 0.001 || abs(longitude) > 0.001
    }
}

public struct RTStopTime: Equatable, Sendable {
    public var stopSequence: Int?
    public var stopID: String?
    public var arrival: Date?
    public var arrivalDelay: Int?
    public var departure: Date?
    public var departureDelay: Int?

    public init(
        stopSequence: Int? = nil,
        stopID: String? = nil,
        arrival: Date? = nil,
        arrivalDelay: Int? = nil,
        departure: Date? = nil,
        departureDelay: Int? = nil
    ) {
        self.stopSequence = stopSequence
        self.stopID = stopID
        self.arrival = arrival
        self.arrivalDelay = arrivalDelay
        self.departure = departure
        self.departureDelay = departureDelay
    }
}

public struct RTTripUpdate: Equatable, Sendable {
    public var entityID: String
    public var trip: RTTrip
    public var vehicleID: String?
    public var stopTimes: [RTStopTime]
    public var timestamp: Date?

    public init(entityID: String = "", trip: RTTrip = RTTrip(), stopTimes: [RTStopTime] = []) {
        self.entityID = entityID
        self.trip = trip
        self.stopTimes = stopTimes
    }
}

public struct RTAlert: Equatable, Sendable {
    public var entityID: String
    public var header: String?
    public var description: String?
}

public struct GTFSRealtimeFeed: Equatable, Sendable {
    public var timestamp: Date?
    public var vehicles: [RTVehicle] = []
    public var tripUpdates: [RTTripUpdate] = []
    public var alerts: [RTAlert] = []

    public init() {}

    /// Decodifica un fichero `.pb` de GTFS-Realtime.
    public init(data: Data) throws {
        var reader = ProtoReader(data)
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, 2):
                var header = try reader.readMessage()
                while let headerField = try header.nextField() {
                    if headerField.number == 3, headerField.wireType == 0 {
                        timestamp = Self.date(try header.readVarint())
                    } else {
                        try header.skip(wireType: headerField.wireType)
                    }
                }
            case (2, 2):
                var entity = try reader.readMessage()
                try decodeEntity(&entity)
            default:
                try reader.skip(wireType: field.wireType)
            }
        }
    }

    private static func date(_ seconds: UInt64) -> Date? {
        seconds == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(Int64(bitPattern: seconds)))
    }

    private mutating func decodeEntity(_ reader: inout ProtoReader) throws {
        var entityID = ""
        var deleted = false
        var vehicle: RTVehicle?
        var tripUpdate: RTTripUpdate?
        var alert: RTAlert?

        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, 2):
                entityID = try reader.readString()
            case (2, 0):
                deleted = try reader.readVarint() != 0
            case (3, 2):
                var sub = try reader.readMessage()
                tripUpdate = try Self.decodeTripUpdate(&sub)
            case (4, 2):
                var sub = try reader.readMessage()
                vehicle = try Self.decodeVehicle(&sub)
            case (5, 2):
                var sub = try reader.readMessage()
                alert = try Self.decodeAlert(&sub)
            default:
                try reader.skip(wireType: field.wireType)
            }
        }
        guard !deleted else {
            return
        }
        if var vehicle = vehicle {
            vehicle.entityID = entityID
            vehicles.append(vehicle)
        }
        if var tripUpdate = tripUpdate {
            tripUpdate.entityID = entityID
            tripUpdates.append(tripUpdate)
        }
        if var alert = alert {
            alert.entityID = entityID
            alerts.append(alert)
        }
    }

    private static func decodeTrip(_ reader: inout ProtoReader) throws -> RTTrip {
        var trip = RTTrip()
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, 2):
                trip.tripID = try reader.readString()
            case (2, 2):
                trip.startTime = try reader.readString()
            case (3, 2):
                trip.startDate = try reader.readString()
            case (5, 2):
                trip.routeID = try reader.readString()
            case (6, 0):
                trip.directionID = Int(truncatingIfNeeded: try reader.readVarint())
            default:
                try reader.skip(wireType: field.wireType)
            }
        }
        return trip
    }

    /// Devuelve (id, etiqueta) de un VehicleDescriptor.
    private static func decodeVehicleDescriptor(_ reader: inout ProtoReader) throws -> (String?, String?) {
        var id: String?
        var label: String?
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, 2):
                id = try reader.readString()
            case (2, 2):
                label = try reader.readString()
            default:
                try reader.skip(wireType: field.wireType)
            }
        }
        return (id, label)
    }

    private static func decodeVehicle(_ reader: inout ProtoReader) throws -> RTVehicle {
        var vehicle = RTVehicle()
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, 2):
                var sub = try reader.readMessage()
                vehicle.trip = try decodeTrip(&sub)
            case (2, 2):
                var position = try reader.readMessage()
                while let positionField = try position.nextField() {
                    switch (positionField.number, positionField.wireType) {
                    case (1, 5):
                        vehicle.latitude = Double(try position.readFloat())
                    case (2, 5):
                        vehicle.longitude = Double(try position.readFloat())
                    case (3, 5):
                        vehicle.bearing = Double(try position.readFloat())
                    case (5, 5):
                        vehicle.speed = Double(try position.readFloat())
                    default:
                        try position.skip(wireType: positionField.wireType)
                    }
                }
            case (3, 0):
                vehicle.currentStopSequence = Int(truncatingIfNeeded: try reader.readVarint())
            case (4, 0):
                vehicle.status = Int(truncatingIfNeeded: try reader.readVarint())
            case (5, 0):
                vehicle.timestamp = date(try reader.readVarint())
            case (7, 2):
                vehicle.stopID = try reader.readString()
            case (8, 2):
                var sub = try reader.readMessage()
                let (id, label) = try decodeVehicleDescriptor(&sub)
                vehicle.vehicleID = id
                vehicle.label = label
            default:
                try reader.skip(wireType: field.wireType)
            }
        }
        return vehicle
    }

    /// Devuelve (hora absoluta, retraso en segundos) de un StopTimeEvent.
    private static func decodeStopTimeEvent(_ reader: inout ProtoReader) throws -> (Date?, Int?) {
        var time: Date?
        var delay: Int?
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, 0):
                // int32: los negativos llegan como varint de 64 bits.
                delay = Int(Int32(truncatingIfNeeded: try reader.readVarint()))
            case (2, 0):
                time = date(try reader.readVarint())
            default:
                try reader.skip(wireType: field.wireType)
            }
        }
        return (time, delay)
    }

    private static func decodeTripUpdate(_ reader: inout ProtoReader) throws -> RTTripUpdate {
        var update = RTTripUpdate()
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, 2):
                var sub = try reader.readMessage()
                update.trip = try decodeTrip(&sub)
            case (2, 2):
                var sub = try reader.readMessage()
                var stopTime = RTStopTime()
                while let stopField = try sub.nextField() {
                    switch (stopField.number, stopField.wireType) {
                    case (1, 0):
                        stopTime.stopSequence = Int(truncatingIfNeeded: try sub.readVarint())
                    case (2, 2):
                        var event = try sub.readMessage()
                        let (time, delay) = try decodeStopTimeEvent(&event)
                        stopTime.arrival = time
                        stopTime.arrivalDelay = delay
                    case (3, 2):
                        var event = try sub.readMessage()
                        let (time, delay) = try decodeStopTimeEvent(&event)
                        stopTime.departure = time
                        stopTime.departureDelay = delay
                    case (4, 2):
                        stopTime.stopID = try sub.readString()
                    default:
                        try sub.skip(wireType: stopField.wireType)
                    }
                }
                update.stopTimes.append(stopTime)
            case (3, 2):
                var sub = try reader.readMessage()
                update.vehicleID = try decodeVehicleDescriptor(&sub).0
            case (4, 0):
                update.timestamp = date(try reader.readVarint())
            default:
                try reader.skip(wireType: field.wireType)
            }
        }
        return update
    }

    /// Primer texto de un TranslatedString.
    private static func decodeTranslatedString(_ reader: inout ProtoReader) throws -> String? {
        var text: String?
        while let field = try reader.nextField() {
            if field.number == 1, field.wireType == 2 {
                var translation = try reader.readMessage()
                while let translationField = try translation.nextField() {
                    if translationField.number == 1, translationField.wireType == 2 {
                        let value = try translation.readString()
                        text = text ?? value
                    } else {
                        try translation.skip(wireType: translationField.wireType)
                    }
                }
            } else {
                try reader.skip(wireType: field.wireType)
            }
        }
        return text
    }

    private static func decodeAlert(_ reader: inout ProtoReader) throws -> RTAlert {
        var alert = RTAlert(entityID: "", header: nil, description: nil)
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (10, 2):
                var sub = try reader.readMessage()
                alert.header = try decodeTranslatedString(&sub)
            case (11, 2):
                var sub = try reader.readMessage()
                alert.description = try decodeTranslatedString(&sub)
            default:
                try reader.skip(wireType: field.wireType)
            }
        }
        return alert
    }
}
