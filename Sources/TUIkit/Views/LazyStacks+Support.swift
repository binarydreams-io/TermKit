//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LazyStacks+Support.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Aligns a lazy stack buffer horizontally within the given width.
func _alignLazyStackBuffer(
  _ buffer: FrameBuffer,
  toWidth width: Int,
  alignment: HorizontalAlignment
) -> FrameBuffer {
  guard buffer.width < width else { return buffer }

  var alignedLines: [String] = []

  let bufferOffset: Int = switch alignment {
  case .leading:
    0
  case .center:
    (width - buffer.width) / 2
  case .trailing:
    width - buffer.width
  }

  let leftPadding = String(repeating: " ", count: bufferOffset)
  let rightPaddingCount = width - bufferOffset - buffer.width

  for line in buffer.lines {
    let lineWidth = line.strippedLength
    let paddedLine = line + String(repeating: " ", count: max(0, buffer.width - lineWidth))
    alignedLines.append(leftPadding + paddedLine + String(repeating: " ", count: max(0, rightPaddingCount)))
  }

  let regions = buffer.regions.map {
    InteractionRegion(
      id: $0.id,
      rect: $0.rect.translatedBy(x: bufferOffset, y: 0)
    )
  }
  return FrameBuffer(lines: alignedLines, regions: regions)
}

// MARK: - Equatable Conformances

extension LazyVStack: @preconcurrency Equatable where Content: Equatable {
  public static func == (lhs: LazyVStack<Content>, rhs: LazyVStack<Content>) -> Bool {
    lhs.alignment == rhs.alignment &&
      lhs.spacing == rhs.spacing &&
      lhs.content == rhs.content
  }
}

extension LazyHStack: @preconcurrency Equatable where Content: Equatable {
  public static func == (lhs: LazyHStack<Content>, rhs: LazyHStack<Content>) -> Bool {
    lhs.alignment == rhs.alignment &&
      lhs.spacing == rhs.spacing &&
      lhs.content == rhs.content
  }
}
