/// A main-actor action invoked when an animation completes.
public typealias AnimationCompletion = @MainActor @Sendable () -> Void

/// Values that control animation during a view update.
public struct Transaction: Sendable {
  /// The animation for value changes, or `nil` for immediate changes.
  public var animation: Animation?
  /// A value that indicates whether animations can run.
  public var areAnimationsEnabled: Bool
  /// A value that indicates whether spatial motion must be reduced.
  public var isReducedMotionEnabled: Bool
  /// The action to invoke after all participating animations complete.
  public var completion: AnimationCompletion?
  /// The instant used to start animations in this transaction.
  public var animationTime: TimeInstant

  @MainActor var completionGroup: TransactionCompletionGroup?

  /// Creates a transaction with animation and motion settings.
  public init(
    animation: Animation? = nil,
    animationsEnabled: Bool = true,
    reduceMotion: Bool = false,
    completion: AnimationCompletion? = nil,
    animationTime: TimeInstant? = nil
  ) {
    self.animation = animation
    self.areAnimationsEnabled = animationsEnabled
    self.isReducedMotionEnabled = reduceMotion
    self.completion = completion
    self.animationTime = animationTime ?? TransactionContext.clock.now
    self.completionGroup = nil
  }

  /// The transaction in the current task-local context.
  public static var current: Transaction {
    TransactionContext.current
  }
}

/// Task-local storage for the current transaction.
public enum TransactionContext {
  static let clock = ContinuousTimeSource()
  /// The transaction visible to the current task.
  ///
  /// Access the projected task-local value to override the transaction for a scoped operation.
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

/// Runs a closure with a task-local transaction.
/// - Complexity: O(1), excluding the body.
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

/// Runs a closure with an animation in the current transaction.
/// - Complexity: O(1), excluding the body.
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
