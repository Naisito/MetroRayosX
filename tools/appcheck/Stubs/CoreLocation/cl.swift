@_exported import Foundation

public typealias CLLocationDegrees = Double
public typealias CLLocationAccuracy = Double
public typealias CLLocationDistance = Double
public typealias CLLocationDirection = Double

public let kCLLocationAccuracyBest: CLLocationAccuracy = -1
public let kCLDistanceFilterNone: CLLocationDistance = -1

public struct CLLocationCoordinate2D {
    public var latitude: CLLocationDegrees
    public var longitude: CLLocationDegrees
    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

open class CLLocation: NSObject {
    public var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 0, longitude: 0) }
    public var horizontalAccuracy: CLLocationAccuracy { 0 }
    public var verticalAccuracy: CLLocationAccuracy { 0 }
    public var altitude: CLLocationDistance { 0 }
    public var timestamp: Date { Date() }
}

open class CLHeading: NSObject {
    public var trueHeading: CLLocationDirection { 0 }
    public var magneticHeading: CLLocationDirection { 0 }
    public var headingAccuracy: CLLocationDirection { 0 }
}

public enum CLAuthorizationStatus: Int32 {
    case notDetermined, restricted, denied, authorizedAlways, authorizedWhenInUse
}

public enum CLAccuracyAuthorization: Int {
    case fullAccuracy, reducedAccuracy
}

public enum CLActivityType: Int {
    case other = 1, automotiveNavigation, fitness, otherNavigation, airborne
}

public protocol CLLocationManagerDelegate: AnyObject {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading)
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool
}

open class CLLocationManager: NSObject {
    public weak var delegate: CLLocationManagerDelegate?
    public var desiredAccuracy: CLLocationAccuracy = 0
    public var distanceFilter: CLLocationDistance = 0
    public var headingFilter: CLLocationDegrees = 0
    public var activityType: CLActivityType = .other
    public var authorizationStatus: CLAuthorizationStatus { .notDetermined }
    public var accuracyAuthorization: CLAccuracyAuthorization { .fullAccuracy }
    public func requestWhenInUseAuthorization() {}
    public func startUpdatingLocation() {}
    public func startUpdatingHeading() {}
    public class func headingAvailable() -> Bool { true }
}
