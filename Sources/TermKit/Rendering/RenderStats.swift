/// Timing and workload measurements for one rendered frame.
public struct RenderStats: Sendable, Hashable {
  /// The total frame duration.
  public var frameDuration: TimeSpan
  /// The duration of view reconciliation.
  public var reconciliationDuration: TimeSpan
  /// The duration of layout.
  public var layoutDuration: TimeSpan
  /// The duration of painting.
  public var paintDuration: TimeSpan
  /// The duration of cell diffing.
  public var diffDuration: TimeSpan
  /// The duration of terminal output.
  public var writeDuration: TimeSpan
  /// The number of encoded output bytes.
  public var encodedByteCount: Int
  /// The number of damaged cells.
  public var damagedCellCount: Int
  /// The number of missed frame budgets.
  public var missedBudgetCount: Int
  /// The number of active animations.
  public var activeAnimationCount: Int
  /// The estimated interner storage size in bytes.
  public var internerByteCount: Int
  /// The number of cells examined by the differ.
  public var scannedCellCount: Int
  /// The number of changed cells.
  public var changedCellCount: Int
  /// The number of generated semantic operations.
  public var operationCount: Int
  /// A Boolean value that indicates whether the frame repainted the full surface.
  public var wasFullRepaint: Bool
  /// A Boolean value that indicates whether the frame rebuilt its interners.
  public var rebuiltInterners: Bool

  /// Creates render statistics.
  public init(
    frameDuration: TimeSpan = .zero,
    reconciliationDuration: TimeSpan = .zero,
    layoutDuration: TimeSpan = .zero,
    paintDuration: TimeSpan = .zero,
    diffDuration: TimeSpan = .zero,
    writeDuration: TimeSpan = .zero,
    encodedByteCount: Int = 0,
    damagedCellCount: Int = 0,
    missedBudgetCount: Int = 0,
    activeAnimationCount: Int = 0,
    internerByteCount: Int = 0,
    scannedCellCount: Int = 0,
    changedCellCount: Int = 0,
    operationCount: Int = 0,
    wasFullRepaint: Bool = false,
    rebuiltInterners: Bool = false
  ) {
    self.frameDuration = frameDuration
    self.reconciliationDuration = reconciliationDuration
    self.layoutDuration = layoutDuration
    self.paintDuration = paintDuration
    self.diffDuration = diffDuration
    self.writeDuration = writeDuration
    self.encodedByteCount = encodedByteCount
    self.damagedCellCount = damagedCellCount
    self.missedBudgetCount = missedBudgetCount
    self.activeAnimationCount = activeAnimationCount
    self.internerByteCount = internerByteCount
    self.scannedCellCount = scannedCellCount
    self.changedCellCount = changedCellCount
    self.operationCount = operationCount
    self.wasFullRepaint = wasFullRepaint
    self.rebuiltInterners = rebuiltInterners
  }
}
