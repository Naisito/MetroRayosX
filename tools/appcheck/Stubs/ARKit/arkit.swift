@_exported import Foundation
@_exported import CoreLocation
@_exported import simd
@_exported import UIKit

open class ARAnchor: NSObject {
    public var identifier: UUID { UUID() }
    public var transform: simd_float4x4 { simd_float4x4() }
}

open class ARPlaneAnchor: ARAnchor {
    public enum Alignment: Int { case horizontal, vertical }
    public var alignment: Alignment { .horizontal }
    public var center: simd_float3 { .zero }
}

open class ARGeoAnchor: ARAnchor {
    public init(coordinate: CLLocationCoordinate2D) {}
    public init(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance) {}
    public var isTracked: Bool { true }
}

open class ARCamera: NSObject {
    public enum TrackingState {
        public enum Reason { case initializing, excessiveMotion, insufficientFeatures, relocalizing }
        case notAvailable
        case limited(Reason)
        case normal
    }
    public var transform: simd_float4x4 { simd_float4x4() }
    public var trackingState: TrackingState { .normal }
}

open class ARFrame: NSObject {
    public var timestamp: TimeInterval { 0 }
    public var camera: ARCamera { ARCamera() }
}

open class ARGeoTrackingStatus: NSObject {
    public enum State: Int { case notAvailable, initializing, localizing, localized }
    public enum Accuracy: Int { case undetermined, low, medium, high }
    public enum StateReason: Int { case none, notAvailableAtLocation, needLocationPermissions }
    public var state: State { .localized }
    public var accuracy: Accuracy { .high }
    public var stateReason: StateReason { .none }
}

open class ARConfiguration: NSObject {
    public enum WorldAlignment: Int { case gravity, gravityAndHeading, camera }
    open class var isSupported: Bool { true }
    public var worldAlignment: WorldAlignment = .gravity
}

open class ARWorldTrackingConfiguration: ARConfiguration {
    public struct PlaneDetection: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let horizontal = PlaneDetection(rawValue: 1)
        public static let vertical = PlaneDetection(rawValue: 2)
    }
    public enum EnvironmentTexturing: Int { case none, manual, automatic }
    public var planeDetection: PlaneDetection = []
    public var environmentTexturing: EnvironmentTexturing = .none
}

open class ARGeoTrackingConfiguration: ARConfiguration {
    public var planeDetection: ARWorldTrackingConfiguration.PlaneDetection = []
    public var environmentTexturing: ARWorldTrackingConfiguration.EnvironmentTexturing = .none
    public class func checkAvailability(completionHandler: @escaping (Bool, Error?) -> Void) {}
    public class func checkAvailability(
        at coordinate: CLLocationCoordinate2D,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {}
}

public struct ARError {
    public static var errorDomain: String { "com.apple.arkit.error" }
    public enum Code: Int {
        case unsupportedConfiguration = 100, sensorUnavailable = 101, sensorFailed = 102, cameraUnauthorized = 103
    }
}

public protocol ARSessionDelegate: AnyObject {
    func session(_ session: ARSession, didUpdate frame: ARFrame)
    func session(_ session: ARSession, didAdd anchors: [ARAnchor])
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor])
    func session(_ session: ARSession, didRemove anchors: [ARAnchor])
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera)
    func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus)
    func session(_ session: ARSession, didFailWithError error: Error)
    func sessionWasInterrupted(_ session: ARSession)
    func sessionInterruptionEnded(_ session: ARSession)
}

open class ARSession: NSObject {
    public struct RunOptions: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let resetTracking = RunOptions(rawValue: 1)
        public static let removeExistingAnchors = RunOptions(rawValue: 2)
    }
    public weak var delegate: ARSessionDelegate?
    public func run(_ configuration: ARConfiguration, options: RunOptions = []) {}
    public func pause() {}
    public func add(anchor: ARAnchor) {}
    public func remove(anchor: ARAnchor) {}
}
