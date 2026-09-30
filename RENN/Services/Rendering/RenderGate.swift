import Foundation

/// Lock-protected "one frame in flight" flag shared by a view's main-thread draw callback and its
/// render queue: while a frame renders, later ticks are dropped instead of queuing up.
final class RenderGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false

    var isBusy: Bool { lock.withLock { busy } }

    func enter() -> Bool {
        lock.withLock {
            guard !busy else { return false }
            busy = true
            return true
        }
    }

    func leave() {
        lock.withLock { busy = false }
    }
}
