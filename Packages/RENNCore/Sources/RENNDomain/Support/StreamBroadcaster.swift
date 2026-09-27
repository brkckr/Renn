import Foundation

/// Fan-out of the latest value to any number of `AsyncStream` subscribers. Each stream keeps
/// only the newest value, so slow consumers can never grow an unbounded queue (04 A05).
/// Intended to be stored inside an actor or a main-actor object.
public struct StreamBroadcaster<Value: Sendable> {
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]

    public init() {}

    public var subscriberCount: Int { continuations.count }

    /// Creates a stream that immediately yields `initial`. `onTermination` receives the
    /// subscriber token so the owner can call `remove(_:)` on its own executor.
    public mutating func makeStream(
        initial: Value,
        onTermination: @escaping @Sendable (UUID) -> Void
    ) -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self, bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        continuations[token] = continuation
        continuation.onTermination = { _ in onTermination(token) }
        continuation.yield(initial)
        return stream
    }

    public mutating func remove(_ token: UUID) {
        continuations[token] = nil
    }

    public func yield(_ value: Value) {
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }
}
