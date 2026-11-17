// Modulo de pega con la parte de Combine que usa la app. Solo firmas.
@_exported import Foundation
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif

public protocol ObservableObject: AnyObject {}

public protocol Publisher {
    associatedtype Output
}

public final class AnyCancellable: Hashable {
    public init() {}
    public static func == (a: AnyCancellable, b: AnyCancellable) -> Bool { a === b }
    public func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
    public func store(in set: inout Set<AnyCancellable>) { set.insert(self) }
}

public struct StubPublisher<Output>: Publisher {
    public init() {}
    public func compactMap<T>(_ transform: @escaping (Output) -> T?) -> StubPublisher<T> { StubPublisher<T>() }
    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable { AnyCancellable() }
}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public var projectedValue: StubPublisher<Value> { StubPublisher<Value>() }
}

extension Timer {
    public final class TimerPublisher {
        public func autoconnect() -> StubPublisher<Date> { StubPublisher<Date>() }
    }
    public static func publish(
        every interval: TimeInterval, tolerance: TimeInterval? = nil, on runLoop: RunLoop, in mode: RunLoop.Mode
    ) -> TimerPublisher { TimerPublisher() }
}
