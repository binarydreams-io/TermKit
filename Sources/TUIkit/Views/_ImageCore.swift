//  🖥️ TUIKit — Terminal UI Kit for Swift
//  _ImageCore.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Image Core

/// Private rendering implementation for ``Image``.
///
/// Handles async image loading, caching, and placeholder display.
/// The raw `RGBAImage` is cached in state; ASCII conversion happens
/// on every render pass so that environment changes (character set,
/// color mode, dithering) take effect immediately.
struct _ImageCore: View, Renderable, Layoutable {
  /// The image source.
  let source: ImageSource

  var body: Never {
    fatalError("_ImageCore renders via Renderable")
  }

  // MARK: - Layoutable

  func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
    let proposedWidth = proposal.width ?? context.availableWidth
    let proposedHeight = proposal.height ?? context.availableHeight
    return .fixed(proposedWidth, proposedHeight)
  }
}
