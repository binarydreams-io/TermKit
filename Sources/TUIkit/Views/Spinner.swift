//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Spinner.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Spinner

/// An animated loading indicator.
///
/// `Spinner` displays a continuously animating indicator to communicate
/// that a task is in progress. It supports multiple visual styles and
/// an optional label.
///
/// The animation runs automatically via a background task that triggers
/// re-renders at a fixed interval. The task is started when the spinner
/// first appears and cancelled when it disappears.
///
/// # Example
///
/// ```swift
/// // Simple dots spinner
/// Spinner()
///
/// // With label
/// Spinner("Loading...")
///
/// // Bouncing style with custom color
/// Spinner("Processing...", style: .bouncing, color: .cyan)
/// ```
///
/// # Styles
///
/// | Style | Visual | Interval |
/// |-------|--------|----------|
/// | `.dots` | `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` | 110ms |
/// | `.line` | `\| / - \\` | 140ms |
/// | `.bouncing` | `■■▇▇▇▇■■■` (with fade trail) | 100ms |
public struct Spinner: View {
  /// The optional label displayed after the spinner.
  let label: String?

  /// The animation style.
  let style: SpinnerStyle

  /// The spinner color (uses theme accent if nil).
  let color: Color?

  /// Unique lifecycle token for this spinner instance.
  let token: String

  /// Creates a spinner with an optional label.
  ///
  /// - Parameters:
  ///   - label: Text displayed after the spinner indicator.
  ///   - style: The animation style (default: `.dots`).
  ///   - color: The spinner color (default: theme accent).
  public init(
    _ label: String? = nil,
    style: SpinnerStyle = .dots,
    color: Color? = nil
  ) {
    self.label = label
    self.style = style
    self.color = color
    self.token = "spinner-\(UUID().uuidString)"
  }

  public var body: some View {
    _SpinnerCore(
      label: label,
      style: style,
      color: color,
      token: token
    )
  }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering and animation of Spinner.
private struct _SpinnerCore: View, Renderable {
  let label: String?
  let style: SpinnerStyle
  let color: Color?
  let token: String

  var body: Never {
    fatalError("_SpinnerCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let lifecycle = context.environment.lifecycle!
    let stateStorage = context.environment.stateStorage!
    let clock = context.environment.runtimeClock
    let invalidationSink = context.environment.renderInvalidationSink

    // Retrieve or create persistent start time for this spinner.
    let timeKey = StateStorage.StateKey(identity: context.identity, propertyIndex: 0)
    let startTimeBox: StateBox<Double> = stateStorage.storage(for: timeKey, default: clock.now())
    stateStorage.markActive(context.identity)

    // Start render-trigger task on first appearance.
    if !lifecycle.hasAppeared(token: token) {
      _ = lifecycle.recordAppear(token: token) {}

      let triggerNanos: UInt64 = 23_800_000 // ~42 animation frames per second
      lifecycle.startTask(token: token, priority: .medium) { [invalidationSink] in
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: triggerNanos)
          guard !Task.isCancelled else { break }
          invalidationSink?.invalidate(.renderOnly)
        }
      }
    } else {
      _ = lifecycle.recordAppear(token: token) {}
    }

    // Register disappear callback to cancel the animation task.
    lifecycle.registerDisappear(token: token) { [lifecycle] in
      lifecycle.cancelTask(token: token)
    }

    // Calculate frame index from elapsed time.
    let elapsed = clock.now() - startTimeBox.value
    let frameCount: Int = switch style {
    case .bouncing:
      SpinnerStyle.bouncingPositions(trackLength: SpinnerStyle.trackWidth).count
    case .dots, .line:
      style.frames.count
    }
    let frameIndex = Int(elapsed / style.interval) % frameCount

    // Resolve color: explicit color > environment foregroundStyle > palette accent
    let effectiveColor = color ?? context.environment.foregroundStyle ?? context.environment.palette.accent
    let resolvedColor = effectiveColor.resolve(with: context.environment.palette)

    // Build spinner text — bouncing renders with colored trail, others are plain.
    let coloredSpinner: String = switch style {
    case .bouncing:
      SpinnerStyle.renderBouncingFrame(
        frameIndex: frameIndex,
        color: resolvedColor,
        trackColor: context.environment.palette.foregroundQuaternary.opacity(0.4)
      )
    case .dots, .line:
      ANSIRenderer.colorize(
        style.frames[frameIndex],
        foreground: resolvedColor
      )
    }

    let output: String
    if let label {
      let styledLabel = ANSIRenderer.colorize(label, foreground: context.environment.palette.foreground)
      output = coloredSpinner + " " + styledLabel
    } else {
      output = coloredSpinner
    }

    return FrameBuffer(text: output)
  }
}
