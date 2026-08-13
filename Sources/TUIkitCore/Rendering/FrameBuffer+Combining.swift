//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameBuffer+Combining.swift
//
//  Created by LAYERED.work
//  License: MIT

extension FrameBuffer {
  /// Stacks another buffer below this one with optional spacing.
  ///
  /// - Parameters:
  ///   - other: The buffer to append below.
  ///   - spacing: Number of empty lines between the two buffers.
  public mutating func appendVertically(_ other: Self, spacing: Int = 0) {
    guard !other.isEmpty else { return }

    // Pre-compute the new width (avoids redundant computation in didSet)
    let newWidth = max(width, other.width)

    // Build combined array
    var combined = lines
    if !combined.isEmpty, spacing > 0 {
      combined.append(contentsOf: repeatElement("", count: spacing))
    }
    let otherOffset = combined.count
    combined.append(contentsOf: other.lines)

    let combinedRegions = regions + other.regions.map {
      InteractionRegion(id: $0.id, rect: $0.rect.translatedBy(x: 0, y: otherOffset))
    }

    // Replace self with new buffer using pre-computed width
    self = FrameBuffer(lines: combined, width: newWidth, regions: combinedRegions)
  }

  /// Places another buffer to the right of this one with optional spacing.
  ///
  /// - Parameters:
  ///   - other: The buffer to append to the right.
  ///   - spacing: Number of space characters between the two buffers.
  public mutating func appendHorizontally(_ other: Self, spacing: Int = 0) {
    let maxHeight = max(height, other.height)
    let myWidth = width
    let spacer = String(repeating: " ", count: spacing)

    // Pre-compute the new width
    let newWidth = myWidth + spacing + other.width

    var result: [String] = []
    result.reserveCapacity(maxHeight)

    for row in 0 ..< maxHeight {
      let left = row < lines.count ? lines[row] : ""
      let right = row < other.lines.count ? other.lines[row] : ""

      // Pad the left side to consistent visible width
      let leftPadded = left.padToVisibleWidth(myWidth)
      result.append(leftPadded + spacer + right)
    }

    let otherOffset = myWidth + spacing
    let combinedRegions = regions + other.regions.map {
      InteractionRegion(id: $0.id, rect: $0.rect.translatedBy(x: otherOffset, y: 0))
    }

    // Replace self with new buffer using pre-computed width
    self = FrameBuffer(lines: result, width: newWidth, regions: combinedRegions)
  }

  /// Layers another buffer on top of this one (ZStack behavior).
  ///
  /// Non-empty characters in the overlay replace characters in the base.
  /// For simplicity, this just overlays line by line.
  ///
  /// - Parameter overlay: The buffer to overlay on top.
  public mutating func overlay(_ overlay: Self) {
    let maxHeight = max(height, overlay.height)
    var result: [String] = []
    for row in 0 ..< maxHeight {
      if row < overlay.lines.count, !overlay.lines[row].isEmpty {
        result.append(overlay.lines[row])
      } else if row < lines.count {
        result.append(lines[row])
      } else {
        result.append("")
      }
    }
    self = Self(lines: result, regions: regions + overlay.regions)
  }
}
