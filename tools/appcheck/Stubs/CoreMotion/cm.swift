@_exported import Foundation

public enum CMAuthorizationStatus: Int {
    case notDetermined, restricted, denied, authorized
}

open class CMAltitudeData: NSObject {
    public var relativeAltitude: NSNumber { 0 }
    public var pressure: NSNumber { 0 }
}

public typealias CMAltitudeHandler = (CMAltitudeData?, Error?) -> Void

open class CMAltimeter: NSObject {
    public class func isRelativeAltitudeAvailable() -> Bool { true }
    public class func authorizationStatus() -> CMAuthorizationStatus { .authorized }
    public func startRelativeAltitudeUpdates(to queue: OperationQueue, withHandler handler: @escaping CMAltitudeHandler) {}
    public func stopRelativeAltitudeUpdates() {}
}
