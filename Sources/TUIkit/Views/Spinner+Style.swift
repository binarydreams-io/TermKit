//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Spinner+Style.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Spinner Style

/// The visual style of a spinner animation.
///
/// TUIKit provides three built-in styles:
///
/// - ``dots``: Braille character rotation (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`)
/// - ``line``: ASCII line rotation (`|/-\`)
/// - ``bouncing``: A highlight block (`▇`) bouncing across a track with a fading trail (Knight Rider / Larson scanner)
public enum SpinnerStyle: Sendable {
  /// Braille character rotation.
  ///
  /// Cycles through: `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏`
  case dots

  /// ASCII line rotation.
  ///
  /// Cycles through: `| / - \`
  case line

  /// A highlight block bouncing across a track of small squares with a
  /// fading trail behind it (Larson scanner / Knight Rider effect).
  ///
  /// The highlight moves back and forth across a fixed 9-position track.
  /// Three trailing positions fade out progressively, creating a smooth
  /// motion trail.
  case bouncing

  /// The animation frames for frame-based styles (dots, line).
  var frames: [String] {
    switch self {
    case .dots:
      ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    case .line:
      ["|", "/", "-", "\\"]
    case .bouncing:
      Self.bouncingPositions(trackLength: Self.trackWidth)
        .map { String($0) }
    }
  }

  /// The fixed animation interval for this style.
  var interval: TimeInterval {
    switch self {
    case .dots: 0.110
    case .line: 0.140
    case .bouncing: 0.100
    }
  }

  /// The fixed track width for the bouncing style (9 positions).
  static let trackWidth = 9

  /// The fixed trail opacities for the bouncing style.
  ///
  /// Index 0 is the highlight itself, followed by 5 fading positions.
  static let trailOpacities: [Double] = [1.0, 0.75, 0.5, 0.35, 0.22, 0.15]

  /// How many positions the highlight overshoots beyond each edge of
  /// the visible track. This lets the trail fade out smoothly at the
  /// edges instead of being cut off abruptly.
  static let edgeOvershoot = 2
}

// MARK: - Internal API

extension SpinnerStyle {
  /// Generates the bounce position sequence for the given track length.
  ///
  /// The highlight travels from `-edgeOvershoot` to
  /// `trackLength - 1 + edgeOvershoot`, then bounces back. Positions
  /// outside the visible range `0..<trackLength` are still valid — the
  /// highlight is off-screen there but its trail remains partially visible.
  ///
  /// - Parameter trackLength: The number of visible positions in the track.
  /// - Returns: An array of highlight positions for each frame.
  static func bouncingPositions(trackLength: Int) -> [Int] {
    let lower = -edgeOvershoot
    let upper = trackLength - 1 + edgeOvershoot
    var positions: [Int] = []

    // Forward: lower → upper
    for position in lower ... upper {
      positions.append(position)
    }

    // Backward: upper-1 → lower+1 (skip endpoints to avoid double-pause)
    for position in stride(from: upper - 1, through: lower + 1, by: -1) {
      positions.append(position)
    }

    return positions
  }

  /// Renders a single bouncing frame with colored trail.
  ///
  /// The highlight position may be outside the visible track (overshoot).
  /// Only positions within `0..<trackWidth` are rendered. Trail positions
  /// that fall within the visible range still get their faded color, even
  /// when the highlight itself is off-screen.
  ///
  /// - Parameters:
  ///   - frameIndex: The current frame index in the bounce sequence.
  ///   - color: The resolved highlight color for the leading dot.
  ///   - trackColor: The color for inactive track positions.
  /// - Returns: An ANSI-colored string representing the track.
  static func renderBouncingFrame(
    frameIndex: Int,
    color: Color,
    trackColor: Color
  ) -> String {
    let positions = bouncingPositions(trackLength: trackWidth)
    let currentPos = positions[frameIndex % positions.count]

    // Determine direction: compare with previous position.
    let prevIndex = (frameIndex - 1 + positions.count) % positions.count
    let prevPos = positions[prevIndex]
    let movingForward = currentPos > prevPos || (currentPos == -edgeOvershoot && prevPos == -edgeOvershoot + 1)

    var result = ""
    for trackIndex in 0 ..< trackWidth {
      let distance = trailDistance(
        from: currentPos,
        to: trackIndex,
        movingForward: movingForward
      )

      if let distance, distance < trailOpacities.count {
        if distance == 0 {
          // Leading highlight dot uses accent color
          result += ANSIRenderer.colorize("●", foreground: color)
        } else {
          // Trail interpolates from highlight to trackColor
          let phase = 1.0 - trailOpacities[distance]
          let fadedColor = Color.lerp(color, trackColor, phase: phase)
          result += ANSIRenderer.colorize("●", foreground: fadedColor)
        }
      } else {
        result += ANSIRenderer.colorize("●", foreground: trackColor)
      }
    }

    return result
  }
}

// MARK: - Private Helpers

extension SpinnerStyle {
  /// Calculates the trail distance from the highlight to a track position.
  ///
  /// Returns `nil` if the position is not in the trail (ahead of the highlight
  /// or too far behind). Distance 0 = highlight itself, 1 = first trail, etc.
  ///
  /// - Parameters:
  ///   - highlight: The current highlight position.
  ///   - target: The track position to check.
  ///   - movingForward: Whether the highlight is moving left→right.
  /// - Returns: The trail distance, or `nil` if not in the trail.
  fileprivate static func trailDistance(
    from highlight: Int,
    to target: Int,
    movingForward: Bool
  ) -> Int? {
    if target == highlight {
      return 0
    }

    // Trail is behind the highlight (opposite to movement direction).
    let offset: Int = if movingForward {
      highlight - target // Trail extends to the left
    } else {
      target - highlight // Trail extends to the right
    }

    return offset > 0 ? offset : nil
  }
}
