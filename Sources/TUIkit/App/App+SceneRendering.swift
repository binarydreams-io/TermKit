//  🖥️ TUIKit — Terminal UI Kit for Swift
//  App+SceneRendering.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Bridge from the `Scene` hierarchy to the `View` rendering system.
///
/// `SceneRenderable` sits outside the `View`/`Renderable` dual system.
/// It connects the `App.body` (which produces a `Scene`) to the view
/// tree rendering via ``renderToBuffer(_:context:)``.
///
/// `RenderLoop` calls `renderScene(context:)` on the scene returned
/// by `App.body`. The scene (typically ``WindowGroup``) then invokes
/// the free function `renderToBuffer` on its content view, entering
/// the standard `Renderable`-or-`body` dispatch.
@MainActor
protocol SceneRenderable {
  /// Renders the scene's content into a ``FrameBuffer``.
  ///
  /// The caller (`RenderLoop`) is responsible for writing the buffer
  /// to the terminal via `FrameDiffWriter`.
  ///
  /// - Parameter context: The rendering context with layout constraints.
  /// - Returns: The rendered frame buffer.
  func renderScene(context: RenderContext) -> FrameBuffer
}

/// Renders the window group's content view into a ``FrameBuffer``.
///
/// This is the bridge from `Scene` to `View` rendering:
/// calls ``renderToBuffer(_:context:)`` on `content` and returns the
/// resulting ``FrameBuffer``. Terminal output (diffing, writing) is
/// handled by `RenderLoop` via `FrameDiffWriter`.
///
/// Renders the window group's content view into a ``FrameBuffer``.
///
/// Like SwiftUI, `WindowGroup` centers its content both horizontally
/// and vertically within the available terminal space.
extension WindowGroup: SceneRenderable {
  func renderScene(context: RenderContext) -> FrameBuffer {
    let buffer = renderToBuffer(content, context: context)

    // Center the content in the available space, like SwiftUI does
    return centerBuffer(buffer, inWidth: context.availableWidth, height: context.availableHeight)
  }

  /// Centers a buffer within the target dimensions.
  private func centerBuffer(_ buffer: FrameBuffer, inWidth targetWidth: Int, height targetHeight: Int) -> FrameBuffer {
    // If buffer already fills the space exactly, return as-is
    if buffer.width == targetWidth, buffer.height == targetHeight {
      return buffer
    }

    var result: [String] = []
    result.reserveCapacity(targetHeight)

    // Calculate offsets for centering
    let verticalOffset = max(0, (targetHeight - buffer.height) / 2)
    let horizontalOffset = max(0, (targetWidth - buffer.width) / 2)
    let leftPadding = String(repeating: " ", count: horizontalOffset)

    // Add top padding (empty lines)
    for _ in 0 ..< verticalOffset {
      result.append(String(repeating: " ", count: targetWidth))
    }

    // Add content lines with horizontal centering
    for row in 0 ..< min(buffer.height, targetHeight - verticalOffset) {
      let line = buffer.lines[row]
      let rightPadding = max(0, targetWidth - horizontalOffset - line.strippedLength)
      result.append(leftPadding + line + String(repeating: " ", count: rightPadding))
    }

    // Add bottom padding (empty lines)
    let bottomPadding = max(0, targetHeight - verticalOffset - buffer.height)
    for _ in 0 ..< bottomPadding {
      result.append(String(repeating: " ", count: targetWidth))
    }

    let centeredRegions = buffer.regions.map {
      InteractionRegion(
        id: $0.id,
        rect: $0.rect.translatedBy(x: horizontalOffset, y: verticalOffset)
      )
    }
    return FrameBuffer(lines: result, regions: centeredRegions)
  }
}
