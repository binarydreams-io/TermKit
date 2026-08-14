/// An error that occurs while comparing cell surfaces.
public enum CellDiffError: Error, Sendable, Equatable {
    /// The front and back surfaces have different sizes.
    case sizeMismatch(front: CellSize, back: CellSize)
    /// A surface contains an invalid wide-cell sequence.
    case malformedSurface(SurfaceError)
}

/// A terminal-independent operation that updates a screen.
public enum SemanticOperation: Sendable, Hashable {
    /// Moves the cursor to a cell point.
    case moveCursor(to: CellPoint)
    /// Selects an interned cell style.
    case setStyle(StyleID)
    /// Writes an interned grapheme at the cursor.
    case write(graphemeID: GraphemeID, displayWidth: UInt8, flags: CellFlags)
}

/// The operations and workload counts from a cell diff.
public struct CellDiffResult: Sendable, Hashable {
    /// The operations that transform the front surface into the back surface.
    public var operations: [SemanticOperation]
    /// The number of cells examined during the diff.
    public var scannedCellCount: Int
    /// The number of cells marked as changed.
    public var changedCellCount: Int

    /// Creates a cell diff result.
    public init(operations: [SemanticOperation], scannedCellCount: Int, changedCellCount: Int) {
        self.operations = operations
        self.scannedCellCount = scannedCellCount
        self.changedCellCount = changedCellCount
    }
}

/// Compares cell surfaces and generates semantic update operations.
public struct CellDiffer: Sendable, Hashable {
    /// The largest unchanged gap that a changed run can rewrite.
    public var maximumRewrittenGap: Int

    /// Creates a cell differ with a maximum rewritten gap.
    public init(maximumRewrittenGap: Int = 2) {
        precondition(maximumRewrittenGap >= 0)
        self.maximumRewrittenGap = maximumRewrittenGap
    }

    /// Returns operations that transform a front surface into a back surface.
    public func diff(front: Surface, back: Surface, damage: DamageTracker? = nil) throws -> CellDiffResult {
        guard front.size == back.size else {
            throw CellDiffError.sizeMismatch(front: front.size, back: back.size)
        }
        do {
            try front.validateWideCells()
            try back.validateWideCells()
        } catch let error as SurfaceError {
            throw CellDiffError.malformedSurface(error)
        }

        let scanDamage: DamageTracker
        if let damage {
            scanDamage = damage
        } else {
            var full = DamageTracker(bounds: back.bounds)
            full.invalidateAll()
            scanDamage = full
        }

        var operations: [SemanticOperation] = []
        var scanned = 0
        var changed = 0
        var activeStyle: StyleID?

        for y in 0..<back.size.height {
            let ranges = scanDamage.ranges(inRow: y)
            guard ranges.isEmpty == false else { continue }
            var marked = Array(repeating: false, count: back.size.width)
            for range in ranges {
                for x in range {
                    scanned += 1
                    let point = CellPoint(x: x, y: y)
                    if front[point] != back[point] {
                        markAtom(at: point, in: front, marks: &marked)
                        markAtom(at: point, in: back, marks: &marked)
                    }
                }
            }
            changed += marked.reduce(0) { $0 + ($1 ? 1 : 0) }

            for run in mergedRuns(from: marked) {
                operations.append(.moveCursor(to: CellPoint(x: run.lowerBound, y: y)))
                var x = run.lowerBound
                while x < run.upperBound {
                    let cell = back[CellPoint(x: x, y: y)]
                    if cell.isContinuation {
                        x += 1
                        continue
                    }
                    if activeStyle != cell.styleID {
                        activeStyle = cell.styleID
                        operations.append(.setStyle(cell.styleID))
                    }
                    let width = cell.displayWidth == 2 ? UInt8(2) : UInt8(1)
                    operations.append(.write(graphemeID: cell.graphemeID, displayWidth: width, flags: cell.flags))
                    x += Int(width)
                }
            }
        }
        return CellDiffResult(operations: operations, scannedCellCount: scanned, changedCellCount: changed)
    }

    private func markAtom(at point: CellPoint, in surface: Surface, marks: inout [Bool]) {
        let cell = surface[point]
        if cell.isContinuation, point.x > 0 {
            marks[point.x - 1] = true
            marks[point.x] = true
        } else if cell.displayWidth == 2, point.x + 1 < marks.count {
            marks[point.x] = true
            marks[point.x + 1] = true
        } else {
            marks[point.x] = true
        }
    }

    private func mergedRuns(from marks: [Bool]) -> [Range<Int>] {
        var rawRuns: [Range<Int>] = []
        var index = 0
        while index < marks.count {
            guard marks[index] else {
                index += 1
                continue
            }
            let start = index
            while index < marks.count, marks[index] { index += 1 }
            rawRuns.append(start..<index)
        }
        guard rawRuns.count > 1 else { return rawRuns }

        var result: [Range<Int>] = [rawRuns[0]]
        for run in rawRuns.dropFirst() {
            let previous = result.removeLast()
            if run.lowerBound - previous.upperBound <= maximumRewrittenGap {
                result.append(previous.lowerBound..<run.upperBound)
            } else {
                result.append(previous)
                result.append(run)
            }
        }
        return result
    }
}

/// A surface and terminal state that can apply semantic operations.
public struct SemanticScreen: Sendable, Equatable {
    /// The current screen surface.
    public private(set) var surface: Surface
    /// The current cursor position.
    public private(set) var cursor: CellPoint
    /// The current style identifier.
    public private(set) var styleID: StyleID

    /// Creates a semantic screen with initial terminal state.
    public init(surface: Surface, cursor: CellPoint = .zero, styleID: StyleID = .default) {
        self.surface = surface
        self.cursor = cursor
        self.styleID = styleID
    }

    /// Applies semantic operations to the screen in sequence order.
    public mutating func apply<S: Sequence>(_ operations: S) throws where S.Element == SemanticOperation {
        for operation in operations {
            switch operation {
            case .moveCursor(let point):
                guard surface.bounds.contains(point) else { throw SurfaceError.outOfBounds(point) }
                cursor = point
            case .setStyle(let identifier):
                styleID = identifier
            case .write(let graphemeID, let displayWidth, let flags):
                try surface.write(
                    graphemeID: graphemeID,
                    at: cursor,
                    styleID: styleID,
                    displayWidth: displayWidth,
                    flags: flags
                )
                cursor = cursor.offsetBy(dx: Int(displayWidth))
            }
        }
    }
}
