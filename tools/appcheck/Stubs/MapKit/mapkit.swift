// Modulo de pega con la parte de MapKit que usa la app. Solo firmas.
@_exported import Foundation
@_exported import CoreLocation
@_exported import UIKit

public struct MKCoordinateRegion {
    public init(center: CLLocationCoordinate2D, latitudinalMeters: CLLocationDistance, longitudinalMeters: CLLocationDistance) {}
}

public protocol MKAnnotation: AnyObject {
    var coordinate: CLLocationCoordinate2D { get }
    var title: String? { get }
    var subtitle: String? { get }
}

open class MKShape: NSObject, MKAnnotation {
    public override init() {}
    open var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 0, longitude: 0) }
    open var title: String?
    open var subtitle: String?
}

open class MKPointAnnotation: MKShape {
    private var stored = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    open override var coordinate: CLLocationCoordinate2D {
        get { stored }
        set { stored = newValue }
    }
}

public protocol MKOverlay: MKAnnotation {}

open class MKPolyline: MKShape, MKOverlay {
    public convenience init(coordinates coords: UnsafePointer<CLLocationCoordinate2D>, count: Int) { self.init() }
}

open class MKMultiPolyline: MKShape, MKOverlay {
    public init(_ polylines: [MKPolyline]) {}
    public var polylines: [MKPolyline] { [] }
}

public enum MKOverlayLevel: Int { case aboveRoads, aboveLabels }
public enum CGLineCap: Int32 { case butt, round, square }

open class MKOverlayRenderer: NSObject {
    public init(overlay: MKOverlay) {}
}

open class MKOverlayPathRenderer: MKOverlayRenderer {
    public var strokeColor: UIColor?
    public var fillColor: UIColor?
    public var lineWidth: CGFloat = 0
    public var lineCap: CGLineCap = .round
    public var lineDashPattern: [NSNumber]?
}

open class MKMultiPolylineRenderer: MKOverlayPathRenderer {
    public init(multiPolyline: MKMultiPolyline) { super.init(overlay: multiPolyline) }
}

public struct MKFeatureDisplayPriority: RawRepresentable {
    public let rawValue: Float
    public init(rawValue: Float) { self.rawValue = rawValue }
    public static let required = MKFeatureDisplayPriority(rawValue: 1000)
    public static let defaultHigh = MKFeatureDisplayPriority(rawValue: 750)
    public static let defaultLow = MKFeatureDisplayPriority(rawValue: 250)
}
public enum MKFeatureVisibility: Int { case adaptive, hidden, visible }

open class MKAnnotationView: UIView {
    public init(annotation: MKAnnotation?, reuseIdentifier: String?) {}
    public var annotation: MKAnnotation?
    public var image: UIImage?
    public var displayPriority: MKFeatureDisplayPriority = .required
    public var canShowCallout = false
}

open class MKMarkerAnnotationView: MKAnnotationView {
    public var markerTintColor: UIColor?
    public var glyphText: String?
    public var titleVisibility: MKFeatureVisibility = .adaptive
}

public final class MKPointOfInterestFilter: NSObject {
    public static let excludingAll = MKPointOfInterestFilter()
    public static let includingAll = MKPointOfInterestFilter()
}

@MainActor @preconcurrency
public protocol MKMapViewDelegate: AnyObject {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView?
}

open class MKMapView: UIView {
    public weak var delegate: MKMapViewDelegate?
    public var showsUserLocation = false
    public var showsCompass = false
    public var showsScale = false
    public var pointOfInterestFilter: MKPointOfInterestFilter?
    public func setRegion(_ region: MKCoordinateRegion, animated: Bool) {}
    public func addOverlay(_ overlay: MKOverlay, level: MKOverlayLevel) {}
    public func addAnnotation(_ annotation: MKAnnotation) {}
    public func addAnnotations(_ annotations: [MKAnnotation]) {}
    public func removeAnnotation(_ annotation: MKAnnotation) {}
    public func dequeueReusableAnnotationView(withIdentifier identifier: String) -> MKAnnotationView? { nil }
}
