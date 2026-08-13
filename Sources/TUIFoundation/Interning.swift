public struct InternerLimits: Sendable, Hashable {
    public var rebuildEntryCount: Int
    public var maximumEntryCount: Int
    public var rebuildByteCount: Int
    public var maximumByteCount: Int

    public init(
        rebuildEntryCount: Int = 65_536,
        maximumEntryCount: Int = 262_144,
        rebuildByteCount: Int = 8 * 1_024 * 1_024,
        maximumByteCount: Int = 32 * 1_024 * 1_024
    ) {
        precondition(rebuildEntryCount > 0 && rebuildEntryCount <= maximumEntryCount)
        precondition(maximumEntryCount <= Int(GraphemeID.maximumRawValue) + 1)
        precondition(rebuildByteCount > 0 && rebuildByteCount <= maximumByteCount)
        self.rebuildEntryCount = rebuildEntryCount
        self.maximumEntryCount = maximumEntryCount
        self.rebuildByteCount = rebuildByteCount
        self.maximumByteCount = maximumByteCount
    }
}

public struct InternerStats: Sendable, Hashable {
    public var entryCount: Int
    public var estimatedByteCount: Int
    public var requiresRebuild: Bool

    public init(entryCount: Int, estimatedByteCount: Int, requiresRebuild: Bool) {
        self.entryCount = entryCount
        self.estimatedByteCount = estimatedByteCount
        self.requiresRebuild = requiresRebuild
    }
}

public enum InternerError: Error, Sendable, Equatable {
    case invalidGrapheme(String)
    case entryLimitExceeded(Int)
    case byteLimitExceeded(Int)
    case unknownGraphemeID(GraphemeID)
    case unknownStyleID(StyleID)
}

public struct GraphemeRemap: Sendable, Equatable {
    private let mapping: [GraphemeID: GraphemeID]

    public init(mapping: [GraphemeID: GraphemeID]) {
        self.mapping = mapping
    }

    public func map(_ oldID: GraphemeID) -> GraphemeID? {
        mapping[oldID]
    }
}

public struct StyleRemap: Sendable, Equatable {
    private let mapping: [StyleID: StyleID]

    public init(mapping: [StyleID: StyleID]) {
        self.mapping = mapping
    }

    public func map(_ oldID: StyleID) -> StyleID? {
        mapping[oldID]
    }
}

public struct GraphemeInterner: Sendable {
    public let limits: InternerLimits
    private var values: [String]
    private var identifiers: [String: GraphemeID]
    private var byteCount: Int

    public init(limits: InternerLimits = InternerLimits()) {
        self.limits = limits
        values = [" "]
        identifiers = [" ": .space]
        byteCount = 1
    }

    public var stats: InternerStats {
        InternerStats(
            entryCount: values.count,
            estimatedByteCount: byteCount,
            requiresRebuild: values.count >= limits.rebuildEntryCount || byteCount >= limits.rebuildByteCount
        )
    }

    public mutating func intern(_ grapheme: Character) throws -> GraphemeID {
        try intern(String(grapheme))
    }

    public mutating func intern(_ grapheme: String) throws -> GraphemeID {
        guard grapheme.count == 1 else { throw InternerError.invalidGrapheme(grapheme) }
        if let existing = identifiers[grapheme] { return existing }
        guard values.count < limits.maximumEntryCount else {
            throw InternerError.entryLimitExceeded(limits.maximumEntryCount)
        }
        let newByteCount = byteCount + grapheme.utf8.count
        guard newByteCount <= limits.maximumByteCount else {
            throw InternerError.byteLimitExceeded(limits.maximumByteCount)
        }
        let identifier = GraphemeID(rawValue: UInt32(values.count))
        values.append(grapheme)
        identifiers[grapheme] = identifier
        byteCount = newByteCount
        return identifier
    }

    public func value(for identifier: GraphemeID) -> String? {
        let index = Int(identifier.rawValue)
        return values.indices.contains(index) ? values[index] : nil
    }

    @discardableResult
    public mutating func rebuild<S: Sequence>(retaining liveIdentifiers: S) throws -> GraphemeRemap where S.Element == GraphemeID {
        var retained = Set(liveIdentifiers)
        retained.insert(.space)
        var replacement = GraphemeInterner(limits: limits)
        var mapping: [GraphemeID: GraphemeID] = [.space: .space]

        for oldIdentifier in retained.sorted() where oldIdentifier != .space {
            guard let value = value(for: oldIdentifier) else {
                throw InternerError.unknownGraphemeID(oldIdentifier)
            }
            mapping[oldIdentifier] = try replacement.intern(value)
        }
        self = replacement
        return GraphemeRemap(mapping: mapping)
    }
}

public struct StyleInterner: Sendable {
    public let limits: InternerLimits
    private var values: [CellStyle]
    private var identifiers: [CellStyle: StyleID]
    private var byteCount: Int

    public init(limits: InternerLimits = InternerLimits()) {
        self.limits = limits
        values = [.default]
        identifiers = [.default: .default]
        byteCount = Self.estimatedBytes(for: .default)
    }

    public var stats: InternerStats {
        InternerStats(
            entryCount: values.count,
            estimatedByteCount: byteCount,
            requiresRebuild: values.count >= limits.rebuildEntryCount || byteCount >= limits.rebuildByteCount
        )
    }

    public mutating func intern(_ style: CellStyle) throws -> StyleID {
        if let existing = identifiers[style] { return existing }
        guard values.count < limits.maximumEntryCount else {
            throw InternerError.entryLimitExceeded(limits.maximumEntryCount)
        }
        let newByteCount = byteCount + Self.estimatedBytes(for: style)
        guard newByteCount <= limits.maximumByteCount else {
            throw InternerError.byteLimitExceeded(limits.maximumByteCount)
        }
        let identifier = StyleID(rawValue: UInt32(values.count))
        values.append(style)
        identifiers[style] = identifier
        byteCount = newByteCount
        return identifier
    }

    public func value(for identifier: StyleID) -> CellStyle? {
        let index = Int(identifier.rawValue)
        return values.indices.contains(index) ? values[index] : nil
    }

    @discardableResult
    public mutating func rebuild<S: Sequence>(retaining liveIdentifiers: S) throws -> StyleRemap where S.Element == StyleID {
        var retained = Set(liveIdentifiers)
        retained.insert(.default)
        var replacement = StyleInterner(limits: limits)
        var mapping: [StyleID: StyleID] = [.default: .default]

        for oldIdentifier in retained.sorted() where oldIdentifier != .default {
            guard let value = value(for: oldIdentifier) else {
                throw InternerError.unknownStyleID(oldIdentifier)
            }
            mapping[oldIdentifier] = try replacement.intern(value)
        }
        self = replacement
        return StyleRemap(mapping: mapping)
    }

    private static func estimatedBytes(for style: CellStyle) -> Int {
        var count = MemoryLayout<CellStyle>.stride
        if case .semantic(let reference)? = style.foreground { count += reference.rawValue.utf8.count }
        if case .semantic(let reference)? = style.background { count += reference.rawValue.utf8.count }
        return count
    }
}
