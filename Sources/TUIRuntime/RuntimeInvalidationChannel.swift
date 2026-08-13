import TUIFoundation

/// Transfers invalidation requests from concurrent work to the runtime event loop.
public final class RuntimeInvalidationChannel: Sendable {
    public typealias WakeHandler = @Sendable () throws -> Void

    private let wakeHandler: WakeHandler?
    private let pending = LockedState<RuntimeInvalidation?>(nil)

    public init(wakeHandler: WakeHandler? = nil) {
        self.wakeHandler = wakeHandler
    }

    public func send(_ invalidation: RuntimeInvalidation = .all) throws {
        let needsWake = pending.withLock { pending in
            let needsWake = pending == nil
            pending = Self.coalesce(pending, invalidation)
            return needsWake
        }

        if needsWake {
            try wakeHandler?()
        }
    }

    func take() -> RuntimeInvalidation? {
        pending.withLock { pending in
            defer { pending = nil }
            return pending
        }
    }

    private static func coalesce(
        _ current: RuntimeInvalidation?,
        _ next: RuntimeInvalidation
    ) -> RuntimeInvalidation {
        switch (current, next) {
        case (.some(.all), _), (_, .all):
            .all
        case let (.some(.region(current)), .region(next)):
            .region(current.union(next))
        case (.none, let next):
            next
        }
    }
}
