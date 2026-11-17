// Modulo de pega con la parte de UIKit que usa la app. Solo firmas.
@_exported import Foundation

open class UIColor {
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public func withAlphaComponent(_ a: CGFloat) -> UIColor { self }
    @discardableResult
    public func getRed(
        _ r: UnsafeMutablePointer<CGFloat>?,
        green: UnsafeMutablePointer<CGFloat>?,
        blue: UnsafeMutablePointer<CGFloat>?,
        alpha: UnsafeMutablePointer<CGFloat>?
    ) -> Bool { true }
    public func setFill() {}
    public func setStroke() {}
    open class var white: UIColor { UIColor(red: 1, green: 1, blue: 1, alpha: 1) }
    open class var label: UIColor { UIColor(red: 1, green: 1, blue: 1, alpha: 1) }
    open class var systemOrange: UIColor { UIColor(red: 1, green: 1, blue: 1, alpha: 1) }
    open class var systemGreen: UIColor { UIColor(red: 1, green: 1, blue: 1, alpha: 1) }
}

open class UIImage {}

public final class CALayer {
    public var zPosition: CGFloat = 0
}

public final class CGContext {
    public func setLineWidth(_ width: CGFloat) {}
    public func fillEllipse(in rect: CGRect) {}
    public func strokeEllipse(in rect: CGRect) {}
}

public final class UIGraphicsImageRendererContext {
    public let cgContext = CGContext()
}

public final class UIGraphicsImageRenderer {
    public init(size: CGSize) {}
    public func image(actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage { UIImage() }
}

@MainActor @preconcurrency
open class UIView {
    public struct AnimationOptions: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let allowUserInteraction = AnimationOptions(rawValue: 2)
        public static let curveLinear = AnimationOptions(rawValue: 3 << 16)
    }
    public init() {}
    public var bounds: CGRect = .zero
    public let layer = CALayer()
    public func addGestureRecognizer(_ g: UIGestureRecognizer) {}
    public class func animate(
        withDuration duration: TimeInterval,
        delay: TimeInterval,
        options: AnimationOptions = [],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {}
}

@MainActor @preconcurrency
open class UIViewController {
    public init() {}
}

open class UIActivityViewController: UIViewController {
    public init(activityItems: [Any], applicationActivities: [Any]?) {}
}

@MainActor @preconcurrency
open class UIGestureRecognizer {
    public enum State { case possible, began, changed, ended, cancelled, failed }
    public var state: State = .possible
    public init(target: Any?, action: Any?) {}
    public func location(in view: UIView?) -> CGPoint { .zero }
}

open class UIPanGestureRecognizer: UIGestureRecognizer {
    public var maximumNumberOfTouches = 1
}

open class UIRotationGestureRecognizer: UIGestureRecognizer {
    public var rotation: CGFloat = 0
}

@MainActor @preconcurrency
public final class UIApplication {
    public static let shared = UIApplication()
    public static let openSettingsURLString = "app-settings:"
    public var isIdleTimerDisabled = false
    public func open(_ url: URL, options: [String: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {}
}

@MainActor @preconcurrency
public final class UIDevice {
    public static let current = UIDevice()
    public var systemVersion: String { "" }
}
