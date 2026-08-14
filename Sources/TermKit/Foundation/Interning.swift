/// Resource limits that control an interner's growth and rebuild threshold.
public struct InternerLimits: Sendable, Hashable {
  /// The entry count that indicates a rebuild is needed.
  public var rebuildEntryCount: Int
  /// The maximum permitted entry count.
  public var maximumEntryCount: Int
  /// The estimated byte count that indicates a rebuild is needed.
  public var rebuildByteCount: Int
  /// The maximum permitted estimated byte count.
  public var maximumByteCount: Int

  /// Creates interner resource limits.
  public init(
    rebuildEntryCount: Int = 65536,
    maximumEntryCount: Int = 262144,
    rebuildByteCount: Int = 8 * 1024 * 1024,
    maximumByteCount: Int = 32 * 1024 * 1024
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

/// Resource statistics for an interner.
public struct InternerStats: Sendable, Hashable {
  /// The number of interned values.
  public var entryCount: Int
  /// The estimated storage size in bytes.
  public var estimatedByteCount: Int
  /// A Boolean value that indicates whether the interner reached a rebuild threshold.
  public var requiresRebuild: Bool

  /// Creates interner statistics.
  public init(entryCount: Int, estimatedByteCount: Int, requiresRebuild: Bool) {
    self.entryCount = entryCount
    self.estimatedByteCount = estimatedByteCount
    self.requiresRebuild = requiresRebuild
  }
}

/// An error that occurs while an interner processes a value or identifier.
public enum InternerError: Error, Sendable, Equatable {
  /// A string does not contain exactly one grapheme.
  case invalidGrapheme(String)
  /// An interner reached its entry limit.
  case entryLimitExceeded(Int)
  /// An interner reached its estimated byte limit.
  case byteLimitExceeded(Int)
  /// A grapheme identifier is not present in the interner.
  case unknownGraphemeID(GraphemeID)
  /// A style identifier is not present in the interner.
  case unknownStyleID(StyleID)
}

/// A mapping from old grapheme identifiers to rebuilt identifiers.
public struct GraphemeRemap: Sendable, Equatable {
  private let mapping: [GraphemeID: GraphemeID]

  /// Creates a grapheme remap from an identifier mapping.
  public init(mapping: [GraphemeID: GraphemeID]) {
    self.mapping = mapping
  }

  /// Returns the rebuilt identifier for an old identifier.
  public func map(_ oldID: GraphemeID) -> GraphemeID? {
    mapping[oldID]
  }
}

/// A mapping from old style identifiers to rebuilt identifiers.
public struct StyleRemap: Sendable, Equatable {
  private let mapping: [StyleID: StyleID]

  /// Creates a style remap from an identifier mapping.
  public init(mapping: [StyleID: StyleID]) {
    self.mapping = mapping
  }

  /// Returns the rebuilt identifier for an old identifier.
  public func map(_ oldID: StyleID) -> StyleID? {
    mapping[oldID]
  }
}

/// A bounded store that assigns compact identifiers to graphemes.
public struct GraphemeInterner: Sendable {
  /// The resource limits for this interner.
  public let limits: InternerLimits
  private var values: [String]
  private var identifiers: [String: GraphemeID]
  private var byteCount: Int

  /// Creates a grapheme interner that contains the reserved space value.
  public init(limits: InternerLimits = InternerLimits()) {
    self.limits = limits
    self.values = [" "]
    self.identifiers = [" ": .space]
    self.byteCount = 1
  }

  /// The interner's current resource statistics.
  public var stats: InternerStats {
    InternerStats(
      entryCount: values.count,
      estimatedByteCount: byteCount,
      requiresRebuild: values.count >= limits.rebuildEntryCount || byteCount >= limits.rebuildByteCount
    )
  }

  /// Interns a grapheme and returns its identifier.
  public mutating func intern(_ grapheme: Character) throws -> GraphemeID {
    try intern(String(grapheme))
  }

  /// Interns a string that contains one grapheme and returns its identifier.
  public mutating func intern(_ grapheme: String) throws -> GraphemeID {
    guard grapheme.count == 1 else { throw InternerError.invalidGrapheme(grapheme) }
    if let existing = identifiers[grapheme] {
      return existing
    }
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

  /// Returns the grapheme for an identifier.
  public func value(for identifier: GraphemeID) -> String? {
    let index = Int(identifier.rawValue)
    return values.indices.contains(index) ? values[index] : nil
  }

  /// Rebuilds the interner with live identifiers and returns their new identifiers.
  @discardableResult
  public mutating func rebuild(retaining liveIdentifiers: some Sequence<GraphemeID>) throws -> GraphemeRemap {
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

/// A bounded store that assigns compact identifiers to cell styles.
public struct StyleInterner: Sendable {
  /// The resource limits for this interner.
  public let limits: InternerLimits
  private var values: [CellStyle]
  private var identifiers: [CellStyle: StyleID]
  private var byteCount: Int

  /// Creates a style interner that contains the reserved default style.
  public init(limits: InternerLimits = InternerLimits()) {
    self.limits = limits
    self.values = [.default]
    self.identifiers = [.default: .default]
    self.byteCount = Self.estimatedBytes(for: .default)
  }

  /// The interner's current resource statistics.
  public var stats: InternerStats {
    InternerStats(
      entryCount: values.count,
      estimatedByteCount: byteCount,
      requiresRebuild: values.count >= limits.rebuildEntryCount || byteCount >= limits.rebuildByteCount
    )
  }

  /// Interns a cell style and returns its identifier.
  public mutating func intern(_ style: CellStyle) throws -> StyleID {
    if let existing = identifiers[style] {
      return existing
    }
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

  /// Returns the cell style for an identifier.
  public func value(for identifier: StyleID) -> CellStyle? {
    let index = Int(identifier.rawValue)
    return values.indices.contains(index) ? values[index] : nil
  }

  /// Rebuilds the interner with live identifiers and returns their new identifiers.
  @discardableResult
  public mutating func rebuild(retaining liveIdentifiers: some Sequence<StyleID>) throws -> StyleRemap {
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
    if case let .semantic(reference)? = style.foreground {
      count += reference.rawValue.utf8.count
    }
    if case let .semantic(reference)? = style.background {
      count += reference.rawValue.utf8.count
    }
    return count
  }
}
