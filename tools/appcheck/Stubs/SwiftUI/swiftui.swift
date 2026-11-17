// Modulo de pega con la parte de SwiftUI que usa la app. Solo firmas.
@_exported import Foundation
@_exported import Combine
@_exported import UIKit

// MARK: - View y ViewBuilder

@MainActor @preconcurrency
public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency var body: Body { get }
}

extension Never: View {
    public var body: Never { fatalError() }
}

public struct EmptyView { public init() {} }
extension EmptyView: View { public var body: Never { fatalError() } }

public struct TupleView<T> { public init(_ value: T) {} }
extension TupleView: View { public var body: Never { fatalError() } }

public struct _ConditionalContent<A, B> { init() {} }
extension _ConditionalContent: View where A: View, B: View { public var body: Never { fatalError() } }

extension Optional: View where Wrapped: View {
    public var body: Never { fatalError() }
}

/// Resultado de cualquier modificador.
public struct _Modified { public init() {} }
extension _Modified: View { public var body: Never { fatalError() } }

@resultBuilder
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildPartialBlock<C: View>(first: C) -> C { first }
    public static func buildPartialBlock<A: View, N: View>(accumulated: A, next: N) -> TupleView<(A, N)> {
        TupleView((accumulated, next))
    }
    public static func buildOptional<C: View>(_ component: C?) -> C? { component }
    public static func buildEither<T: View, F: View>(first: T) -> _ConditionalContent<T, F> { _ConditionalContent() }
    public static func buildEither<T: View, F: View>(second: F) -> _ConditionalContent<T, F> { _ConditionalContent() }
}

// MARK: - Tipos basicos

public struct LocalizedStringKey: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {}
    public init(_ value: String) {}
}

public struct Font {
    public enum Weight { case regular, medium, semibold, bold }
    public enum Design { case `default`, monospaced, rounded, serif }
    public enum TextStyle { case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2 }
    public static let largeTitle = Font()
    public static let title = Font()
    public static let title2 = Font()
    public static let title3 = Font()
    public static let headline = Font()
    public static let subheadline = Font()
    public static let body = Font()
    public static let callout = Font()
    public static let footnote = Font()
    public static let caption = Font()
    public static let caption2 = Font()
    public static func system(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font { Font() }
    public static func system(_ style: TextStyle, design: Design = .default) -> Font { Font() }
    public func weight(_ weight: Weight) -> Font { self }
    public func monospacedDigit() -> Font { self }
}

public protocol ShapeStyle {}

public struct Color: Hashable {
    public init(red: Double, green: Double, blue: Double) {}
    init() {}
    public static let clear = Color()
    public static let black = Color()
    public static let white = Color()
    public static let gray = Color()
    public static let red = Color()
    public static let green = Color()
    public static let blue = Color()
    public static let orange = Color()
    public static let yellow = Color()
    public static let primary = Color()
    public static let secondary = Color()
    public static let accentColor = Color()
    public func opacity(_ opacity: Double) -> Color { self }
}
extension Color: ShapeStyle {}
extension Color: View { public var body: Never { fatalError() } }

extension ShapeStyle where Self == Color {
    public static var clear: Color { Color() }
    public static var black: Color { Color() }
    public static var white: Color { Color() }
    public static var red: Color { Color() }
    public static var green: Color { Color() }
    public static var orange: Color { Color() }
    public static var yellow: Color { Color() }
    public static var primary: Color { Color() }
    public static var secondary: Color { Color() }
}

public struct Material: ShapeStyle {
    public static let regular = Material()
    public static let thin = Material()
    public static let ultraThin = Material()
}
extension ShapeStyle where Self == Material {
    public static var regularMaterial: Material { Material() }
    public static var thinMaterial: Material { Material() }
    public static var ultraThinMaterial: Material { Material() }
}

public struct AnyShapeStyle: ShapeStyle {
    public init<S: ShapeStyle>(_ style: S) {}
}

public struct FillStyle { public init() {} }

public protocol Shape: View {}
extension Shape {
    public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View { _Modified() }
    public func fill<S: ShapeStyle>(_ content: S) -> some View { _Modified() }
}
public enum RoundedCornerStyle { case circular, continuous }
public struct RoundedRectangle {
    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {}
}
extension RoundedRectangle: Shape { public var body: Never { fatalError() } }
public struct Circle { public init() {} }
extension Circle: Shape { public var body: Never { fatalError() } }

public enum HorizontalAlignment { case leading, center, trailing }
public enum VerticalAlignment { case top, center, bottom, firstTextBaseline, lastTextBaseline }
public enum Alignment { case center, leading, trailing, top, bottom, topLeading, topTrailing, bottomLeading, bottomTrailing }
public enum TextAlignment { case leading, center, trailing }
public enum Edge {
    public struct Set: OptionSet {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1)
        public static let leading = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)
        public static let all: Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
    }
}
public struct SafeAreaRegions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let all = SafeAreaRegions(rawValue: 1)
}

// MARK: - Vistas

public struct Text {
    public init(_ key: LocalizedStringKey) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ content: S) {}
}
extension Text: View { public var body: Never { fatalError() } }

public struct Image {
    public init(systemName: String) {}
    public init(_ name: String) {}
}
extension Image: View { public var body: Never { fatalError() } }

public struct Spacer { public init(minLength: CGFloat? = nil) {} }
extension Spacer: View { public var body: Never { fatalError() } }

public struct VStack<Content: View> {
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {}
}
extension VStack: View { public var body: Never { fatalError() } }
public struct HStack<Content: View> {
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {}
}
extension HStack: View { public var body: Never { fatalError() } }
public struct ZStack<Content: View> {
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {}
}
extension ZStack: View { public var body: Never { fatalError() } }

public struct ScrollView<Content: View> {
    public init(@ViewBuilder content: () -> Content) {}
}
extension ScrollView: View { public var body: Never { fatalError() } }
public struct List<Content: View> {
    public init(@ViewBuilder content: () -> Content) {}
}
extension List: View { public var body: Never { fatalError() } }
public struct Form<Content: View> {
    public init(@ViewBuilder content: () -> Content) {}
}
extension Form: View { public var body: Never { fatalError() } }
public struct NavigationView<Content: View> {
    public init(@ViewBuilder content: () -> Content) {}
}
extension NavigationView: View { public var body: Never { fatalError() } }
public struct TabView<Content: View> {
    public init(@ViewBuilder content: () -> Content) {}
}
extension TabView: View { public var body: Never { fatalError() } }

public struct Label<Title: View, Icon: View> {
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {}
}
extension Label: View { public var body: Never { fatalError() } }
extension Label where Title == Text, Icon == Image {
    public init(_ titleKey: LocalizedStringKey, systemImage name: String) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, systemImage name: String) {}
}

public struct ButtonRole: Equatable {
    public static let destructive = ButtonRole()
    public static let cancel = ButtonRole()
}
public struct Button<Label: View> {
    public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {}
    public init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {}
}
extension Button: View { public var body: Never { fatalError() } }
extension Button where Label == Text {
    public init(_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) {}
}

public struct NavigationLink<Label: View, Destination: View> {
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {}
    public init(destination: Destination, @ViewBuilder label: () -> Label) {}
}
extension NavigationLink: View { public var body: Never { fatalError() } }

public struct Link<Label: View> {
    public init(destination: URL, @ViewBuilder label: () -> Label) {}
}
extension Link: View { public var body: Never { fatalError() } }
extension Link where Label == Text {
    public init(_ titleKey: LocalizedStringKey, destination: URL) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, destination: URL) {}
}

public struct ProgressView<Label: View, CurrentValueLabel: View> {}
extension ProgressView: View { public var body: Never { fatalError() } }
extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    public init() {}
}
extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    public init(_ titleKey: LocalizedStringKey) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S) {}
}

public struct Picker<Label: View, SelectionValue: Hashable, Content: View> {}
extension Picker: View { public var body: Never { fatalError() } }
extension Picker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {}
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {}
}

public struct Section<Parent, Content, Footer> {}
extension Section: View where Parent: View, Content: View, Footer: View { public var body: Never { fatalError() } }
extension Section where Parent: View, Content: View, Footer: View {
    public init(header: Parent, footer: Footer, @ViewBuilder content: () -> Content) {}
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent, @ViewBuilder footer: () -> Footer) {}
}
extension Section where Parent == EmptyView, Content: View, Footer: View {
    public init(footer: Footer, @ViewBuilder content: () -> Content) {}
}
extension Section where Parent: View, Content: View, Footer == EmptyView {
    public init(header: Parent, @ViewBuilder content: () -> Content) {}
}
extension Section where Parent == EmptyView, Content: View, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content) {}
}

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content> {}
extension ForEach: View where Content: View { public var body: Never { fatalError() } }
extension ForEach where Content: View {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> some View { _Modified() }
}
extension ForEach where ID == Data.Element.ID, Content: View, Data.Element: Identifiable {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}

// MARK: - Estilos

public protocol PrimitiveButtonStyle {}
public struct PlainButtonStyle: PrimitiveButtonStyle { public init() {} }
public struct BorderedButtonStyle: PrimitiveButtonStyle { public init() {} }
public struct BorderedProminentButtonStyle: PrimitiveButtonStyle { public init() {} }
extension PrimitiveButtonStyle where Self == PlainButtonStyle { public static var plain: PlainButtonStyle { PlainButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderedButtonStyle { public static var bordered: BorderedButtonStyle { BorderedButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle {
    public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() }
}

public protocol ListStyle {}
public struct InsetGroupedListStyle: ListStyle { public init() {} }
extension ListStyle where Self == InsetGroupedListStyle { public static var insetGrouped: InsetGroupedListStyle { InsetGroupedListStyle() } }

public protocol NavigationViewStyle {}
public struct StackNavigationViewStyle: NavigationViewStyle { public init() {} }
extension NavigationViewStyle where Self == StackNavigationViewStyle { public static var stack: StackNavigationViewStyle { StackNavigationViewStyle() } }

public protocol TextSelectability {}
public struct EnabledTextSelectability: TextSelectability {}
extension TextSelectability where Self == EnabledTextSelectability { public static var enabled: EnabledTextSelectability { EnabledTextSelectability() } }

public enum ControlSize { case mini, small, regular, large }
public enum NavigationBarItem {
    public enum TitleDisplayMode { case automatic, inline, large }
}

// MARK: - Modificadores

extension View {
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View { _Modified() }
    public func padding(_ length: CGFloat) -> some View { _Modified() }
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View { _Modified() }
    public func font(_ font: Font?) -> some View { _Modified() }
    public func foregroundColor(_ color: Color?) -> some View { _Modified() }
    public func lineLimit(_ number: Int?) -> some View { _Modified() }
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View { _Modified() }
    public func fixedSize() -> some View { _Modified() }
    public func position(_ position: CGPoint) -> some View { _Modified() }
    public func allowsHitTesting(_ enabled: Bool) -> some View { _Modified() }
    public func disabled(_ disabled: Bool) -> some View { _Modified() }
    public func tag<V: Hashable>(_ tag: V) -> some View { _Modified() }
    public func tint(_ tint: Color?) -> some View { _Modified() }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View { _Modified() }
    public func frame(
        minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View { _Modified() }
    public func background<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View { _Modified() }
    public func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> some View { _Modified() }
    public func overlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> some View { _Modified() }
    public func onAppear(perform action: (() -> Void)? = nil) -> some View { _Modified() }
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View { _Modified() }
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View { _Modified() }
    public func onReceive<P: Publisher>(_ publisher: P, perform action: @escaping (P.Output) -> Void) -> some View { _Modified() }
    public func sheet<Content: View>(
        isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content
    ) -> some View { _Modified() }
    public func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View { _Modified() }
    public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View { _Modified() }
    public func listStyle<S: ListStyle>(_ style: S) -> some View { _Modified() }
    public func navigationViewStyle<S: NavigationViewStyle>(_ style: S) -> some View { _Modified() }
    public func textSelection<S: TextSelectability>(_ selectability: S) -> some View { _Modified() }
    public func controlSize(_ controlSize: ControlSize) -> some View { _Modified() }
    public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View { _Modified() }
    public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View { _Modified() }
    @_disfavoredOverload public func navigationTitle<S: StringProtocol>(_ title: S) -> some View { _Modified() }
    public func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View { _Modified() }
    public func tabItem<V: View>(@ViewBuilder _ label: () -> V) -> some View { _Modified() }
    public func environmentObject<T: ObservableObject>(_ object: T) -> some View { _Modified() }
}

// MARK: - Property wrappers

@propertyWrapper
public struct Binding<Value> {
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {}
    public var wrappedValue: Value {
        get { fatalError() }
        nonmutating set {}
    }
    public var projectedValue: Binding<Value> { self }
}

@propertyWrapper
public struct State<Value> {
    public init(wrappedValue value: Value) {}
    public init(initialValue value: Value) {}
    public var wrappedValue: Value {
        get { fatalError() }
        nonmutating set {}
    }
    public var projectedValue: Binding<Value> { fatalError() }
}
extension State where Value: ExpressibleByNilLiteral {
    public init() {}
}

@propertyWrapper
public struct StateObject<ObjectType: ObservableObject> {
    nonisolated public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) {}
    @MainActor @preconcurrency public var wrappedValue: ObjectType { fatalError() }
}

@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject> {
    public init(wrappedValue: ObjectType) {}
    public init(initialValue: ObjectType) {}
    @MainActor @preconcurrency public var wrappedValue: ObjectType {
        get { fatalError() }
        set {}
    }
}

@propertyWrapper
public struct EnvironmentObject<ObjectType: ObservableObject> {
    public init() {}
    @MainActor @preconcurrency public var wrappedValue: ObjectType { fatalError() }
}

@propertyWrapper
public struct AppStorage<Value> {
    let key: String
    public var wrappedValue: Value {
        get { fatalError() }
        nonmutating set {}
    }
    public var projectedValue: Binding<Value> { fatalError() }
}
extension AppStorage where Value == Bool {
    public init(wrappedValue: Bool, _ key: String, store: UserDefaults? = nil) { self.key = key }
}
extension AppStorage where Value == String {
    public init(wrappedValue: String, _ key: String, store: UserDefaults? = nil) { self.key = key }
}

public enum ScenePhase: Comparable { case background, inactive, active }
public struct EnvironmentValues {
    public var scenePhase: ScenePhase { .active }
}
@propertyWrapper
public struct Environment<Value> {
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {}
    public var wrappedValue: Value { fatalError() }
}

// MARK: - App y Scene

@MainActor @preconcurrency
public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Body { get }
}
extension Never: Scene {}

public struct _ModifiedScene { public init() {} }
extension _ModifiedScene: Scene { public var body: Never { fatalError() } }

@resultBuilder
public struct SceneBuilder {
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
}

public struct WindowGroup<Content: View> {
    public init(@ViewBuilder content: () -> Content) {}
}
extension WindowGroup: Scene { public var body: Never { fatalError() } }

extension Scene {
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some Scene { _ModifiedScene() }
}

@MainActor @preconcurrency
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Body { get }
    @MainActor @preconcurrency init()
}

// MARK: - UIKit dentro de SwiftUI

@MainActor @preconcurrency
public struct UIViewRepresentableContext<Representable: UIViewRepresentable> {
    public let coordinator: Representable.Coordinator
}

@MainActor @preconcurrency
public protocol UIViewRepresentable: View where Body == Never {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void
    typealias Context = UIViewRepresentableContext<Self>
    @MainActor @preconcurrency func makeUIView(context: Context) -> UIViewType
    @MainActor @preconcurrency func updateUIView(_ uiView: UIViewType, context: Context)
    @MainActor @preconcurrency func makeCoordinator() -> Coordinator
}
extension UIViewRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Coordinator { () }
}
extension UIViewRepresentable {
    public var body: Never { fatalError() }
}

@MainActor @preconcurrency
public struct UIViewControllerRepresentableContext<Representable: UIViewControllerRepresentable> {
    public let coordinator: Representable.Coordinator
}

@MainActor @preconcurrency
public protocol UIViewControllerRepresentable: View where Body == Never {
    associatedtype UIViewControllerType: UIViewController
    associatedtype Coordinator = Void
    typealias Context = UIViewControllerRepresentableContext<Self>
    @MainActor @preconcurrency func makeUIViewController(context: Context) -> UIViewControllerType
    @MainActor @preconcurrency func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context)
    @MainActor @preconcurrency func makeCoordinator() -> Coordinator
}
extension UIViewControllerRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Coordinator { () }
}
extension UIViewControllerRepresentable {
    public var body: Never { fatalError() }
}
