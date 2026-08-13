import TUIFoundation

public struct RenderStats: Sendable, Hashable {
    public var frameDuration: TUIDuration
    public var reconciliationDuration: TUIDuration
    public var layoutDuration: TUIDuration
    public var paintDuration: TUIDuration
    public var diffDuration: TUIDuration
    public var writeDuration: TUIDuration
    public var encodedByteCount: Int
    public var damagedCellCount: Int
    public var missedBudgetCount: Int
    public var activeAnimationCount: Int
    public var internerByteCount: Int
    public var scannedCellCount: Int
    public var changedCellCount: Int
    public var operationCount: Int
    public var wasFullRepaint: Bool
    public var rebuiltInterners: Bool

    public init(
        frameDuration: TUIDuration = .zero,
        reconciliationDuration: TUIDuration = .zero,
        layoutDuration: TUIDuration = .zero,
        paintDuration: TUIDuration = .zero,
        diffDuration: TUIDuration = .zero,
        writeDuration: TUIDuration = .zero,
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
