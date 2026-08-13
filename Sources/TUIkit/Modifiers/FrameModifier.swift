//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Frame Dimension

/// Represents a frame dimension that can be a fixed value or infinity.
public enum FrameDimension: Equatable, Sendable {
  /// A fixed size in characters/lines.
  case fixed(Int)

  /// Expand to fill all available space.
  case infinity

  /// The special infinity value for frame constraints.
  public static let max: FrameDimension = .infinity
}

// MARK: - Flexible Frame View

/// A view that applies flexible frame constraints to its content.
///
/// This view handles min/max constraints and renders content with
/// the appropriate available space.
public struct FlexibleFrameView<Content: View>: View {
  /// The content view to constrain.
  let content: Content

  /// The minimum width in characters, or nil for no minimum.
  let minWidth: Int?

  /// The ideal width in characters, or nil to use intrinsic size.
  let idealWidth: Int?

  /// The maximum width constraint, or nil for no maximum.
  let maxWidth: FrameDimension?

  /// The minimum height in lines, or nil for no minimum.
  let minHeight: Int?

  /// The ideal height in lines, or nil to use intrinsic size.
  let idealHeight: Int?

  /// The maximum height constraint, or nil for no maximum.
  let maxHeight: FrameDimension?

  /// The alignment of the content within the frame.
  let alignment: Alignment

  public var body: Never {
    fatalError("FlexibleFrameView renders via Renderable")
  }
}

// MARK: - Equatable Conformance

extension FlexibleFrameView: @preconcurrency Equatable where Content: Equatable {
  public static func == (lhs: FlexibleFrameView<Content>, rhs: FlexibleFrameView<Content>) -> Bool {
    lhs.content == rhs.content &&
      lhs.minWidth == rhs.minWidth &&
      lhs.idealWidth == rhs.idealWidth &&
      lhs.maxWidth == rhs.maxWidth &&
      lhs.minHeight == rhs.minHeight &&
      lhs.idealHeight == rhs.idealHeight &&
      lhs.maxHeight == rhs.maxHeight &&
      lhs.alignment == rhs.alignment
  }
}
