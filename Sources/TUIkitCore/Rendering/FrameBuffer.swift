//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameBuffer.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A 2D text buffer that views render into before flushing to the terminal.
///
/// `FrameBuffer` enables a two-pass rendering approach:
/// 1. Each view renders into its own buffer (measuring its size)
/// 2. Layout containers combine child buffers (horizontally, vertically, or layered)
/// 3. The final root buffer is flushed to the terminal
///
/// Each line in the buffer is a string that may contain ANSI escape codes.
///
/// - Important: This is framework infrastructure used as the rendering primitive in
///   ``ViewModifier/modify(buffer:context:)``. Most developers don't need to interact
///   with this type directly.
public struct FrameBuffer: Sendable, Equatable {
  /// The lines of rendered content (may contain ANSI escape codes).
  ///
  /// Mutating `lines` directly recomputes the cached ``width``.
  public var lines: [String] {
    didSet { recomputeWidth() }
  }

  /// The width of the buffer (the length of the longest line in visible characters).
  ///
  /// This is a stored property, recomputed automatically whenever
  /// ``lines`` is mutated. Accessing `width` is O(1) — the expensive
  /// ANSI-stripping regex runs only once per mutation, not per access.
  public private(set) var width: Int

  /// Interaction regions in deterministic back-to-front order.
  ///
  /// Later regions are visually above earlier regions. A hit tester can search
  /// this array in reverse to resolve the topmost interactive target.
  public var regions: [InteractionRegion]

  /// The height of the buffer (number of lines).
  public var height: Int {
    lines.count
  }

  /// Whether the buffer is empty.
  public var isEmpty: Bool {
    lines.isEmpty || lines.allSatisfy(\.isEmpty)
  }

  /// Creates an empty buffer.
  public init() {
    self.lines = []
    self.width = 0
    self.regions = []
  }

  /// Creates a buffer from an array of lines.
  ///
  /// - Parameters:
  ///   - lines: The text lines.
  ///   - regions: Interaction regions in back-to-front order.
  public init(lines: [String], regions: [InteractionRegion] = []) {
    self.lines = lines
    self.width = Self.computeWidth(lines)
    self.regions = Self.clippedRegions(regions, width: width, height: lines.count)
  }

  /// Initializer that accepts pre-computed width.
  ///
  /// Use this when the width is already known to avoid redundant computation.
  public init(lines: [String], width: Int, regions: [InteractionRegion] = []) {
    self.lines = lines
    self.width = width
    self.regions = Self.clippedRegions(regions, width: width, height: lines.count)
  }

  /// Creates a buffer containing a single line.
  ///
  /// - Parameters:
  ///   - text: The text content.
  ///   - regions: Interaction regions in back-to-front order.
  public init(text: String, regions: [InteractionRegion] = []) {
    self.lines = [text]
    self.width = text.strippedLength
    self.regions = Self.clippedRegions(regions, width: width, height: 1)
  }

  /// Creates a spacer buffer with the specified height.
  ///
  /// The buffer contains lines with a single space character to ensure
  /// it is not considered "empty" by layout algorithms. This is important
  /// for Spacer views which need to occupy vertical space even without
  /// visible content.
  ///
  /// - Parameter height: The number of lines.
  public init(emptyWithHeight height: Int) {
    // Use a single space instead of empty string so the buffer
    // is not considered "empty" by appendVertically
    self.lines = Array(repeating: " ", count: height)
    self.width = 1
    self.regions = []
  }

  /// Creates a buffer of empty spaces with the specified width and height.
  ///
  /// Used by horizontal stacks for Spacer views which need to occupy
  /// horizontal space across multiple rows.
  ///
  /// - Parameters:
  ///   - width: The width in characters.
  ///   - height: The number of lines.
  public init(emptyWithWidth width: Int, height: Int) {
    self.lines = Array(repeating: String(repeating: " ", count: width), count: height)
    self.width = width
    self.regions = []
  }

  // MARK: - Combining Arrays

  /// Creates a vertically stacked buffer from an array of buffers.
  ///
  /// TupleViews use this to combine their children vertically by default
  /// (the parent stack then decides the actual layout direction).
  ///
  /// - Parameter buffers: The buffers to stack vertically.
  public init(verticallyStacking buffers: [Self]) {
    self.init()
    for buffer in buffers {
      appendVertically(buffer)
    }
  }
}

// MARK: - Private Helpers

extension FrameBuffer {
  /// Recomputes the cached ``width`` from the current ``lines``.
  ///
  /// Called automatically by the `didSet` observer on ``lines``.
  private mutating func recomputeWidth() {
    width = Self.computeWidth(lines)
    regions = Self.clippedRegions(regions, width: width, height: height)
  }

  /// Computes the visible width of a set of lines.
  ///
  /// - Parameter lines: The lines to measure.
  /// - Returns: The length of the longest line in visible characters.
  fileprivate static func computeWidth(_ lines: [String]) -> Int {
    lines.map(\.strippedLength).max() ?? 0
  }

  /// Clips interaction regions to a buffer's bounds and removes empty regions.
  fileprivate static func clippedRegions(
    _ regions: [InteractionRegion],
    width: Int,
    height: Int
  ) -> [InteractionRegion] {
    let bounds = TerminalCellRect(x: 0, y: 0, width: width, height: height)
    return regions.compactMap { region in
      guard let rect = region.rect.intersection(bounds) else { return nil }
      return InteractionRegion(id: region.id, rect: rect)
    }
  }
}
