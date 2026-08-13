public typealias AnimationCompletion = @MainActor @Sendable () -> Void

import TUIFoundation
import TUIViewGraph

public struct Transaction: Sendable {
    public var animation: Animation?
    public var animationsEnabled: Bool
    public var reduceMotion: Bool
    public var completion: AnimationCompletion?
    public var animationTime: TimeInstant

    @MainActor var completionGroup: TransactionCompletionGroup?

    public init(
        animation: Animation? = nil,
        animationsEnabled: Bool = true,
        reduceMotion: Bool = false,
        completion: AnimationCompletion? = nil,
        animationTime: TimeInstant? = nil
    ) {
        self.animation = animation
        self.animationsEnabled = animationsEnabled
        self.reduceMotion = reduceMotion
        self.completion = completion
        self.animationTime = animationTime ?? TransactionContext.clock.now()
        completionGroup = nil
    }

    public static var current: Transaction {
        TransactionContext.current
    }
}

public enum TransactionContext {
    static let clock = ContinuousTimeSource()
    @TaskLocal public static var current = Transaction()
}

@MainActor
final class TransactionCompletionGroup {
    private var completion: AnimationCompletion?
    private var participantCount = 0
    private var pendingCount = 0
    private var isClosed = false
    private var isCancelled = false

    init(completion: @escaping AnimationCompletion) {
        self.completion = completion
    }

    func register() -> TransactionCompletionParticipant {
        guard isClosed == false else {
            return TransactionCompletionParticipant(group: nil)
        }
        participantCount += 1
        pendingCount += 1
        return TransactionCompletionParticipant(group: self)
    }

    func close() {
        isClosed = true
        completeIfReady()
    }

    func participantCompleted() {
        pendingCount -= 1
        completeIfReady()
    }

    func participantCancelled() {
        pendingCount -= 1
        isCancelled = true
        completion = nil
    }

    private func completeIfReady() {
        guard isClosed, participantCount > 0, pendingCount == 0, isCancelled == false else {
            return
        }
        let action = completion
        completion = nil
        action?()
    }
}

@MainActor
final class TransactionCompletionParticipant {
    private var group: TransactionCompletionGroup?

    init(group: TransactionCompletionGroup?) {
        self.group = group
    }

    func complete() {
        let group = group
        self.group = nil
        group?.participantCompleted()
    }

    func cancel() {
        let group = group
        self.group = nil
        group?.participantCancelled()
    }
}

@MainActor
public func withTransaction<Result>(
    _ transaction: Transaction,
    _ body: @MainActor () throws -> Result
) rethrows -> Result {
    var transaction = transaction
    let completionGroup = transaction.completion.map(TransactionCompletionGroup.init(completion:))
    transaction.completion = nil
    transaction.completionGroup = completionGroup
    defer { completionGroup?.close() }

    return try ViewInvalidationContext.$transaction.withValue(transaction) {
        try TransactionContext.$current.withValue(transaction) {
            try body()
        }
    }
}

@MainActor
public func withAnimation<Result>(
    _ animation: Animation? = .default,
    completion: AnimationCompletion? = nil,
    _ body: @MainActor () throws -> Result
) rethrows -> Result {
    var transaction = Transaction.current
    transaction.animation = animation
    transaction.completion = completion
    return try withTransaction(transaction, body)
}
