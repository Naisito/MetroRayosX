import Foundation

/// Un tren colocado sobre una ruta.
public struct TrainPosition: Equatable, Sendable, Identifiable {
    public let id: String
    public let linea: String?
    /// Índice en `MetroModel.rutas`.
    public let rutaIndex: Int
    /// Metros desde el principio de la ruta hasta la cabeza del tren.
    public let chainage: Double
    public let detenido: Bool
    /// Estación en la que está o a la que se dirige.
    public let estacionID: String?

    public init(
        id: String,
        linea: String?,
        rutaIndex: Int,
        chainage: Double,
        detenido: Bool,
        estacionID: String?
    ) {
        self.id = id
        self.linea = linea
        self.rutaIndex = rutaIndex
        self.chainage = chainage
        self.detenido = detenido
        self.estacionID = estacionID
    }
}

/// Coloca los trenes de los feeds GTFS-Realtime sobre las rutas de la red.
///
/// El feed del CTB para Metro Bilbao no da coordenadas dentro del túnel: las
/// actualizaciones de viaje traen la hora de llegada a cada parada que falta
/// y las posiciones solo listan los trenes parados en una estación. Por eso
/// la posición sale de interpolar entre paradas, y es una función continua
/// de la hora: basta volver a llamar con otra `now` para animar el tren.
public struct TrainLocator: Sendable {
    /// Velocidad media entre estaciones, en m/s, para el tramo anterior a la
    /// primera parada anunciada.
    public var cruiseSpeed = 12.0
    /// Parada en estación, en segundos, cuando el feed no da hora de salida.
    public var defaultDwell = 20.0
    /// Segundos que un tren sigue dibujado en su última parada.
    public var lingerAtTerminus = 45.0
    /// Correspondencia explícita `route_id` del feed -> id de línea.
    /// En Metro Bilbao `route_id` vale siempre "MB", así que la línea se
    /// deduce de las paradas del viaje.
    public var routeToLine: [String: String] = [:]
    /// Sufijo del id de ruta para cada `direction_id` del feed. En Metro
    /// Bilbao: 1 = hacia Plentzia/Kabiezes (rutas "-0"), 2 = hacia
    /// Etxebarri/Basauri (rutas "-1"). Solo desempata.
    public var directionSuffix: [Int: String] = [1: "-0", 2: "-1"]
    /// Distancia máxima a una ruta para aceptar una posición con coordenadas.
    public var maxSnapDistance = 120.0

    private let rutas: [RouteGeometry]
    private let stationByStop: [String: String]
    private let lineIDs: [String]

    public init(rutas: [RouteGeometry], estaciones: [Estacion]) {
        self.rutas = rutas
        var byStop: [String: String] = [:]
        for estacion in estaciones {
            byStop[estacion.id] = estacion.id
            for parada in estacion.paradas {
                byStop[parada] = estacion.id
            }
        }
        stationByStop = byStop
        var ids: [String] = []
        for ruta in rutas where !ids.contains(ruta.ruta.linea) {
            ids.append(ruta.ruta.linea)
        }
        // Las más largas primero: "L10" no debe casar con "L1".
        lineIDs = ids.sorted { $0.count > $1.count }
    }

    public init(model: MetroModel) {
        self.init(rutas: model.rutas, estaciones: model.red.estaciones)
    }

    /// Línea de la red para un `route_id` del feed, si se puede saber.
    public func lineID(forRoute routeID: String?) -> String? {
        guard let routeID = routeID, !routeID.isEmpty else {
            return nil
        }
        if let line = routeToLine[routeID] {
            return line
        }
        let upper = routeID.uppercased()
        return lineIDs.first { upper.contains($0.uppercased()) }
    }

    /// Todos los trenes en circulación a la hora `now`.
    public func locate(tripUpdates: [RTTripUpdate], vehicles: [RTVehicle], now: Date) -> [TrainPosition] {
        var result: [String: TrainPosition] = [:]
        for update in tripUpdates {
            if let train = locate(update: update, now: now) {
                result[train.id] = train
            }
        }
        // Las posiciones solo rellenan los trenes que no salen del horario.
        for vehicle in vehicles {
            let id = TrainLocator.trainID(trip: vehicle.trip, vehicleID: vehicle.vehicleID, entityID: vehicle.entityID)
            if result[id] == nil, let train = locate(vehicle: vehicle, id: id, now: now) {
                result[id] = train
            }
        }
        return result.values.sorted { $0.id < $1.id }
    }

    static func trainID(trip: RTTrip, vehicleID: String?, entityID: String) -> String {
        if let tripID = trip.tripID, !tripID.isEmpty {
            return tripID
        }
        if let vehicleID = vehicleID, !vehicleID.isEmpty {
            return vehicleID
        }
        return entityID
    }

    private func candidateRoutes(line: String?) -> [Int] {
        let all = Array(rutas.indices)
        guard let line = line else {
            return all
        }
        let matching = all.filter { rutas[$0].ruta.linea == line }
        return matching.isEmpty ? all : matching
    }

    static func ease(_ f: Double) -> Double {
        let x = min(max(f, 0), 1)
        return x * x * (3 - 2 * x)
    }

    // MARK: - Actualizaciones de viaje

    private struct TimedStop {
        var estacionID: String
        var arrival: Date
        var departure: Date
    }

    private struct PlacedStop {
        var estacionID: String
        var chainage: Double
        var arrival: Date
        var departure: Date
    }

    /// Posición de un viaje a la hora `now`, o `nil` si no está circulando.
    public func locate(update: RTTripUpdate, now: Date) -> TrainPosition? {
        let timed: [TimedStop] = update.stopTimes.compactMap { stopTime in
            guard let stopID = stopTime.stopID, let estacionID = stationByStop[stopID],
                  let arrival = stopTime.arrival ?? stopTime.departure
            else {
                return nil
            }
            let departure = stopTime.departure ?? arrival.addingTimeInterval(defaultDwell)
            return TimedStop(estacionID: estacionID, arrival: arrival, departure: max(departure, arrival))
        }
        guard !timed.isEmpty else {
            return nil
        }

        let line = lineID(forRoute: update.trip.routeID)
        let suffix = update.trip.directionID.flatMap { directionSuffix[$0] }

        // La ruta buena es la que recorre las paradas en orden creciente.
        var bestRoute: Int?
        var bestScore = 0.0
        for index in candidateRoutes(line: line) {
            let route = rutas[index]
            let chainages = timed.compactMap { route.chainage(ofStation: $0.estacionID) }
            var score = 0.0
            if chainages.count >= 2 {
                for i in 1..<chainages.count where chainages[i] != chainages[i - 1] {
                    score += chainages[i] > chainages[i - 1] ? 1 : -1
                }
            } else if let only = chainages.first, route.length > 0 {
                // Una sola parada: es el final del viaje.
                score = 0.5 * only / route.length
            }
            if let suffix = suffix, route.ruta.id.hasSuffix(suffix) {
                score += 0.25
            }
            if score > bestScore {
                bestScore = score
                bestRoute = index
            }
        }
        guard let routeIndex = bestRoute else {
            return nil
        }
        let route = rutas[routeIndex]

        let stops = TrainLocator.place(timed, on: route)
        guard let last = stops.last else {
            return nil
        }
        let id = TrainLocator.trainID(trip: update.trip, vehicleID: update.vehicleID, entityID: update.entityID)

        func train(_ chainage: Double, stopped: Bool, station: String?) -> TrainPosition {
            TrainPosition(
                id: id,
                linea: line ?? route.ruta.linea,
                rutaIndex: routeIndex,
                chainage: chainage,
                detenido: stopped,
                estacionID: station
            )
        }

        // Viaje terminado: se queda un momento en la última parada.
        if now >= last.arrival {
            guard now.timeIntervalSince(last.arrival) <= lingerAtTerminus else {
                return nil
            }
            return train(last.chainage, stopped: true, station: last.estacionID)
        }

        // Primera parada de la que aún no ha salido (la última nunca «sale»).
        var index = stops.count - 1
        for i in stops.indices where now < stops[i].departure {
            index = i
            break
        }
        let next = stops[index]
        if now >= next.arrival {
            return train(next.chainage, stopped: true, station: next.estacionID)
        }

        if index > 0 {
            let previous = stops[index - 1]
            let span = next.arrival.timeIntervalSince(previous.departure)
            let f = span > 0 ? now.timeIntervalSince(previous.departure) / span : 1
            let chainage = previous.chainage + (next.chainage - previous.chainage) * TrainLocator.ease(f)
            return train(chainage, stopped: false, station: next.estacionID)
        }

        // Antes de la primera parada anunciada: viene de la estación anterior.
        let startChainage = route.stop(before: next.chainage)?.chainage ?? max(next.chainage - 600, 0)
        let travelTime = max((next.chainage - startChainage) / cruiseSpeed, 20)
        let remaining = next.arrival.timeIntervalSince(now)
        if remaining > travelTime + 90 {
            // Todavía no ha salido de cabecera.
            return nil
        }
        if remaining >= travelTime {
            return train(startChainage, stopped: true, station: next.estacionID)
        }
        let f = 1 - remaining / travelTime
        let chainage = startChainage + (next.chainage - startChainage) * TrainLocator.ease(f)
        return train(chainage, stopped: false, station: next.estacionID)
    }

    /// Pone las paradas sobre la ruta y arregla las que rompen el orden.
    ///
    /// El feed manda Urduliz con el `stop_id` de Gobela: una parada que queda
    /// fuera de sitio se cambia por la estación de la ruta que falta entre sus
    /// vecinas y, si no se puede, se descarta.
    private static func place(_ timed: [TimedStop], on route: RouteGeometry) -> [PlacedStop] {
        let raw: [PlacedStop] = timed.compactMap { stop in
            route.chainage(ofStation: stop.estacionID).map {
                PlacedStop(estacionID: stop.estacionID, chainage: $0, arrival: stop.arrival, departure: stop.departure)
            }
        }
        guard !raw.isEmpty else {
            return []
        }

        // Las paradas «en su sitio» son la subsecuencia creciente más larga
        // (quedándose con las primeras en caso de empate).
        let count = raw.count
        var best = [Int](repeating: 1, count: count)
        var link = [Int](repeating: -1, count: count)
        for i in 0..<count {
            for j in 0..<i where raw[j].chainage < raw[i].chainage && best[j] + 1 > best[i] {
                best[i] = best[j] + 1
                link[i] = j
            }
        }
        var end = 0
        for i in 0..<count where best[i] > best[end] {
            end = i
        }
        var inOrder = Set<Int>()
        var cursor = end
        while cursor >= 0 {
            inOrder.insert(cursor)
            cursor = link[cursor]
        }

        var used = Set(raw.map { $0.estacionID })
        var placed: [PlacedStop] = []
        for i in raw.indices {
            var stop = raw[i]
            if !inOrder.contains(i) {
                // Fuera de sitio: buscar la estación que falta en ese hueco.
                let previous = placed.last?.chainage
                let following = raw.indices.first { $0 > i && inOrder.contains($0) }.map { raw[$0].chainage }
                let gap = route.stops.filter { candidate in
                    !used.contains(candidate.estacionID)
                        && (previous == nil || candidate.chainage > previous!)
                        && (following == nil || candidate.chainage < following!)
                }
                // La vecina inmediata de la parada siguiente (o de la anterior).
                guard let replacement = following != nil ? gap.last : gap.first else {
                    continue
                }
                stop.estacionID = replacement.estacionID
                stop.chainage = replacement.chainage
                used.insert(replacement.estacionID)
            }
            placed.append(stop)
        }

        // Ninguna salida puede ser posterior a la llegada a la parada siguiente.
        if placed.count >= 2 {
            for i in 0..<(placed.count - 1) where placed[i].departure > placed[i + 1].arrival {
                placed[i].departure = max(placed[i].arrival, placed[i + 1].arrival)
            }
        }
        return placed
    }

    // MARK: - Posiciones de vehículos

    private func locate(vehicle: RTVehicle, id: String, now: Date) -> TrainPosition? {
        let line = lineID(forRoute: vehicle.trip.routeID)
        let suffix = vehicle.trip.directionID.flatMap { directionSuffix[$0] }
        let candidates = candidateRoutes(line: line)
        let estacionID = vehicle.stopID.flatMap { stationByStop[$0] }
        // Sin estado, un vehículo con parada asignada está parado en ella.
        let stopped = vehicle.status == 1 || (vehicle.status == nil && estacionID != nil)

        if vehicle.hasPosition, let latitude = vehicle.latitude, let longitude = vehicle.longitude {
            let point = GeoPoint(latitude: latitude, longitude: longitude)
            var best: (index: Int, chainage: Double, cost: Double)?
            for index in candidates {
                let route = rutas[index]
                guard let hit = route.project(point), hit.distance <= maxSnapDistance else {
                    continue
                }
                // Las dos rutas de una línea pasan por el mismo sitio: se elige
                // la que va en el sentido del tren.
                var cost = hit.distance
                if let bearing = vehicle.bearing {
                    let difference = abs(TrainLocator.angleDifference(bearing, route.bearing(at: hit.chainage)))
                    if difference > 90 {
                        cost += 1000
                    }
                } else if let suffix = suffix, !route.ruta.id.hasSuffix(suffix) {
                    cost += 1000
                }
                if best == nil || cost < best!.cost {
                    best = (index, hit.chainage, cost)
                }
            }
            guard let found = best else {
                return nil
            }
            var chainage = found.chainage
            if !stopped, let speed = vehicle.speed, speed > 0, let timestamp = vehicle.timestamp {
                let age = min(max(now.timeIntervalSince(timestamp), 0), 30)
                chainage = min(chainage + speed * age, rutas[found.index].length)
            }
            return TrainPosition(
                id: id,
                linea: line ?? rutas[found.index].ruta.linea,
                rutaIndex: found.index,
                chainage: chainage,
                detenido: stopped,
                estacionID: estacionID
            )
        }

        // Sin coordenadas: solo se sabe la parada actual o la siguiente.
        guard let estacionID = estacionID else {
            return nil
        }
        let ordered = candidates.sorted { a, b in
            let aMatches = suffix.map { rutas[a].ruta.id.hasSuffix($0) } ?? false
            let bMatches = suffix.map { rutas[b].ruta.id.hasSuffix($0) } ?? false
            return aMatches && !bMatches
        }
        for index in ordered {
            let route = rutas[index]
            guard let stopChainage = route.chainage(ofStation: estacionID) else {
                continue
            }
            if stopped {
                return TrainPosition(
                    id: id, linea: line ?? route.ruta.linea, rutaIndex: index,
                    chainage: stopChainage, detenido: true, estacionID: estacionID
                )
            }
            let previous = route.stop(before: stopChainage)?.chainage ?? max(stopChainage - 600, 0)
            return TrainPosition(
                id: id, linea: line ?? route.ruta.linea, rutaIndex: index,
                chainage: (previous + stopChainage) / 2, detenido: false, estacionID: estacionID
            )
        }
        return nil
    }

    /// Diferencia entre dos rumbos, en grados, en (−180, 180].
    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        var difference = (a - b).truncatingRemainder(dividingBy: 360)
        if difference > 180 {
            difference -= 360
        } else if difference <= -180 {
            difference += 360
        }
        return difference
    }
}
