//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderCache+Types.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

extension RenderCache {
  /// Aggregated cache performance statistics.
  ///
  /// Tracks hit/miss/store/clear counts. Use ``stats`` for cumulative
  /// totals. ``logFrameStats()`` logs the delta since the last
  /// ``beginRenderPass()``.
  public struct Stats: Equatable {
    /// Number of successful cache lookups (view and size matched).
    public var hits: Int = 0

    /// Number of failed cache lookups (identity missing, view changed, or size changed).
    public var misses: Int = 0

    /// Number of entries stored (including overwrites).
    public var stores: Int = 0

    /// Number of times ``clearAll()`` was called.
    public var clears: Int = 0

    /// Number of times ``clearAffected(by:)`` was called.
    public var subtreeClears: Int = 0

    /// Creates a new Stats instance with default values.
    public init(
      hits: Int = 0,
      misses: Int = 0,
      stores: Int = 0,
      clears: Int = 0,
      subtreeClears: Int = 0
    ) {
      self.hits = hits
      self.misses = misses
      self.stores = stores
      self.clears = clears
      self.subtreeClears = subtreeClears
    }

    /// The total number of lookups (hits + misses).
    public var lookups: Int {
      hits + misses
    }

    /// The cache hit rate as a value between 0 and 1, or 0 if no lookups occurred.
    public var hitRate: Double {
      lookups > 0 ? Double(hits) / Double(lookups) : 0
    }

    /// Returns the per-element difference between this snapshot and an earlier one.
    public func delta(since earlier: Self) -> Self {
      Self(
        hits: hits - earlier.hits,
        misses: misses - earlier.misses,
        stores: stores - earlier.stores,
        clears: clears - earlier.clears,
        subtreeClears: subtreeClears - earlier.subtreeClears
      )
    }
  }

  /// A cached rendering result for a single view identity.
  public struct CacheEntry {
    /// The type-erased view value at the time of caching.
    ///
    /// Cast back to the concrete `Equatable` type for comparison.
    public let viewSnapshot: Any

    /// The rendered output buffer.
    public let buffer: FrameBuffer

    /// The available width when this entry was cached.
    public let contextWidth: Int

    /// The available height when this entry was cached.
    public let contextHeight: Int

    /// Creates a new cache entry.
    public init(viewSnapshot: Any, buffer: FrameBuffer, contextWidth: Int, contextHeight: Int) {
      self.viewSnapshot = viewSnapshot
      self.buffer = buffer
      self.contextWidth = contextWidth
      self.contextHeight = contextHeight
    }
  }

  /// Whether debug logging is enabled via the `TUIKIT_DEBUG_RENDER` environment variable.
  public static let debugEnabled: Bool = ProcessInfo.processInfo.environment["TUIKIT_DEBUG_RENDER"] == "1"
}
