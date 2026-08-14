/// An overlay host exposed by the design layer.
public typealias DesignOverlayHost<Content: Sendable> = OverlayHost<Content>

extension OverlayHost where Content == AnyView {
  /// Presents a toast and removes it when its timeline expires.
  public func present(_ toast: Toast, zIndex: Int = 1000) {
    let timeline = toast.timeline { [weak self] id in
      self?.dismiss(id)
    }
    present(
      OverlayPresentation(
        id: toast.id,
        content: AnyView(timeline),
        kind: .toast,
        zIndex: zIndex
      )
    )
  }
}

/// A preferred terminal width for dialogs.
public enum DialogWidth: Int, CaseIterable, Sendable, Hashable {
  /// A compact 60-column dialog.
  case compact = 60
  /// A regular 88-column dialog.
  case regular = 88
  /// A wide 116-column dialog.
  case wide = 116
}

extension DialogSurface: SemanticRenderable, View where Content == String {
  /// Returns the dialog size constrained by a proposal.
  /// - Complexity: O(1).
  public nonisolated func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
    CellSize(width: max(0, proposal.width ?? preferredWidth.rawValue), height: max(0, proposal.height ?? 3))
  }

  /// Paints the dialog backdrop, panel, and text content.
  /// - Complexity: O(*w* × *h*), where the terms are the clipped surface dimensions.
  public nonisolated func paint(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    let backdrop = CellStyle(background: .rgba(RGBA.black.applyingOpacity(0.45)))
    let backdropID = try resources.internPaintStyle(backdrop)
    surface.clear(context.clip, with: .makeBlank(styleID: backdropID))
    let panel = frame(in: context.clip.size, contentHeight: min(context.clip.height, 3))
      .offsetBy(dx: context.origin.x, dy: context.origin.y)
    let panelStyle = CellStyle(foreground: .rgba(.white), background: .rgba(RGBA(redByte: 38, greenByte: 40, blueByte: 48)))
    let panelID = try resources.internPaintStyle(panelStyle)
    surface.clear(panel, with: .makeBlank(styleID: panelID))
    let textContext = PaintContext(
      clip: panel.inset(by: EdgeInsets(horizontal: 2, vertical: 1)),
      origin: panel.origin.offsetBy(dx: 2, dy: 1)
    )
    let child = try Text(content, style: panelStyle).paint(into: &surface, context: textContext, resources: &resources)
    return semanticNode(frame: panel, children: [child])
  }

  /// The modal, focusable primitive node descriptor.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    [
      NodeDescriptor(
        type: Self.self,
        primitive: self,
        focus: FocusMetadata(id: FocusID(rawValue: id.rawValue), isFocusable: true),
        hitTest: HitTestMetadata(disablesDescendants: false, isEnabled: true, zIndex: 100, modalScope: id.rawValue),
        dirtyOnUpdate: .layout
      )
    ]
  }
}

/// The content and presentation metadata for a centered dialog.
public struct DialogSurface<Content: Sendable>: Sendable {
  /// The overlay identifier.
  public var id: OverlayID
  /// The dialog title used by semantics.
  public var title: String
  /// The preferred dialog width.
  public var preferredWidth: DialogWidth
  /// The minimum horizontal terminal margin.
  public var horizontalMargin: Int
  /// The dialog content.
  public var content: Content

  /// Creates a dialog surface.
  public init(
    id: OverlayID,
    title: String,
    content: Content,
    preferredWidth: DialogWidth = .regular,
    horizontalMargin: Int = 2
  ) {
    self.id = id
    self.title = title
    self.preferredWidth = preferredWidth
    self.horizontalMargin = max(0, horizontalMargin)
    self.content = content
  }

  /// Returns a centered dialog frame for a terminal size.
  /// - Complexity: O(1).
  public func frame(in terminalSize: CellSize, contentHeight: Int) -> CellRect {
    let width = min(preferredWidth.rawValue, max(0, terminalSize.width - horizontalMargin * 2))
    let height = min(max(0, contentHeight), terminalSize.height)
    return CellRect(
      x: max(0, (terminalSize.width - width) / 2),
      y: max(0, (terminalSize.height - height) / 2),
      width: width,
      height: height
    )
  }

  /// Creates a modal overlay presentation for the dialog.
  /// - Complexity: O(1).
  public func presentation(zIndex: Int = 100) -> OverlayPresentation<DialogSurface<Content>> {
    OverlayPresentation(
      id: id,
      content: self,
      kind: .dialog,
      isModal: true,
      dismissOnEscape: true,
      zIndex: zIndex
    )
  }

  /// Creates the dialog's semantic node.
  /// - Complexity: O(1).
  public func semanticNode(frame: CellRect? = nil, children: [SemanticNode] = []) -> SemanticNode {
    SemanticNode(
      id: SemanticID(rawValue: "dialog-\(id.rawValue)"),
      role: .dialog,
      label: title,
      state: .modal,
      actions: [.dismiss],
      frame: frame,
      children: children
    )
  }
}

/// The semantic status of a toast.
public enum ToastKind: String, Sendable, Hashable, CaseIterable {
  /// Informational status.
  case info
  /// Successful status.
  case success
  /// Warning status.
  case warning
  /// Error status.
  case error
}

/// A timed status message presented as an overlay.
public struct Toast: Sendable, Hashable {
  /// The overlay identifier.
  public var id: OverlayID
  /// The message text.
  public var message: String
  /// The semantic status kind.
  public var kind: ToastKind
  /// The maximum terminal width.
  public var maximumWidth: Int
  /// The creation instant.
  public var createdAt: TimeInstant
  /// The total display duration.
  public var duration: TimeSpan
  /// The fade-out duration.
  public var fade: TimeSpan

  /// Creates a timed toast.
  public init(
    id: OverlayID,
    message: String,
    createdAt: TimeInstant,
    kind: ToastKind = .info,
    maximumWidth: Int = 44,
    duration: TimeSpan = .seconds(4),
    fade: TimeSpan = .milliseconds(160)
  ) {
    precondition(duration > .zero, "A toast duration must be positive.")
    precondition(fade >= .zero, "A toast fade duration must not be negative.")
    self.id = id
    self.message = message
    self.kind = kind
    self.maximumWidth = max(1, maximumWidth)
    self.createdAt = createdAt
    self.duration = duration
    self.fade = min(fade, duration)
  }

  /// Returns the toast frame for a terminal size.
  /// - Complexity: O(*n*), where *n* is the message length.
  public func frame(in terminalSize: CellSize) -> CellRect {
    guard terminalSize.isEmpty == false else { return .zero }
    let width = min(maximumWidth, max(1, terminalSize.width - 2))
    let lines = wrappedLines(width: max(1, width - 2))
    return CellRect(
      x: max(0, terminalSize.width - width - 1),
      y: min(1, max(0, terminalSize.height - 1)),
      width: width,
      height: min(lines.count, terminalSize.height)
    )
  }

  /// Returns the toast opacity at an instant.
  /// - Complexity: O(1).
  public func opacity(at instant: TimeInstant, reduceMotion: Bool) -> Double {
    guard instant >= createdAt else { return 0 }
    guard reduceMotion == false else { return instant < createdAt.advanced(by: duration) ? 1 : 0 }
    let end = createdAt.advanced(by: duration)
    if instant >= end {
      return 0
    }
    guard fade > .zero else { return 1 }
    let remaining = instant.duration(to: end)
    return remaining >= fade ? 1 : max(0, remaining.seconds / fade.seconds)
  }

  /// Wraps the message to a terminal width.
  /// - Complexity: O(*n*), where *n* is the message length.
  public func wrappedLines(width: Int? = nil) -> [String] {
    let width = max(1, width ?? maximumWidth)
    var lines: [String] = []
    var current = ""
    for word in message.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
      if TerminalWidth.width(of: word) > width {
        if current.isEmpty == false {
          lines.append(current)
          current = ""
        }
        var remainder = Substring(word)
        while TerminalWidth.width(of: String(remainder)) > width {
          var consumed = 0
          var chunk = ""
          var chunkWidth = 0
          for grapheme in remainder {
            let graphemeWidth = TerminalWidth.width(of: grapheme)
            if chunkWidth + graphemeWidth <= width {
              chunk.append(grapheme)
              chunkWidth += graphemeWidth
              consumed += 1
            } else if consumed == 0, graphemeWidth == 2 {
              chunk = "�"
              consumed = 1
              break
            } else {
              break
            }
          }
          lines.append(chunk)
          remainder.removeFirst(consumed)
        }
        current = String(remainder)
      } else if current.isEmpty {
        current = word
      } else if TerminalWidth.width(of: current) + 1 + TerminalWidth.width(of: word) <= width {
        current += " \(word)"
      } else {
        lines.append(current)
        current = word
      }
    }
    if current.isEmpty == false {
      lines.append(current)
    }
    return lines.isEmpty ? [""] : lines
  }

  /// Creates an overlay presentation for the toast.
  /// - Complexity: O(1).
  public func presentation(zIndex: Int = 1000) -> OverlayPresentation<Toast> {
    OverlayPresentation(id: id, content: self, kind: .toast, zIndex: zIndex)
  }

  /// Creates a timeline view that invokes an action when the toast expires.
  @MainActor
  public func timeline(
    onExpire: @escaping @MainActor @Sendable (_ id: OverlayID) -> Void
  ) -> ToastTimelineView {
    ToastTimelineView(toast: self, onExpire: onExpire)
  }

  /// Creates the toast's semantic status node.
  /// - Complexity: O(1).
  public func semanticNode(frame: CellRect? = nil) -> SemanticNode {
    SemanticNode(id: SemanticID(rawValue: "toast-\(id.rawValue)"), role: .status, label: message, frame: frame)
  }
}

@MainActor
private final class ToastExpirationController {
  private var didExpire = false
  private let action: @MainActor @Sendable () -> Void

  init(action: @escaping @MainActor @Sendable () -> Void) {
    self.action = action
  }

  func expire() {
    guard didExpire == false else { return }
    didExpire = true
    action()
  }
}

private struct ToastExpirationView: View {
  let controller: ToastExpirationController

  var graphBody: [NodeDescriptor] {
    [
      NodeDescriptor(
        type: Self.self,
        lifecycle: NodeLifecycle(
          onMount: { _ in controller.expire() },
          onUpdate: { _ in controller.expire() }
        )
      )
    ]
  }
}

private struct ToastTimelineContent: View {
  let toast: Toast
  let instant: TimeInstant
  let reduceMotion: Bool
  let controller: ToastExpirationController

  var graphBody: [NodeDescriptor] {
    let end = toast.createdAt.advanced(by: toast.duration)
    if instant >= end {
      return ToastExpirationView(controller: controller).graphBody
    }
    let fadeStart = end.advanced(by: .nanoseconds(-toast.fade.nanoseconds))
    if reduceMotion == false, toast.fade > .zero, instant >= fadeStart {
      return TimelineView(.animation()) { context in
        toast.opacity(toast.opacity(at: context.instant, reduceMotion: false))
      }.graphBody
    }
    return toast.opacity(1).graphBody
  }
}

/// A timeline-driven view that fades and expires a toast.
public struct ToastTimelineView: View {
  /// The toast displayed by the view.
  public let toast: Toast
  @Environment(ReduceMotionEnvironmentKey.self) private var reduceMotion
  private let controller: ToastExpirationController

  /// Creates a toast timeline view.
  public init(
    toast: Toast,
    onExpire: @escaping @MainActor @Sendable (_ id: OverlayID) -> Void
  ) {
    self.toast = toast
    self.controller = ToastExpirationController { onExpire(toast.id) }
  }

  /// The timeline node descriptors for the toast.
  public var graphBody: [NodeDescriptor] {
    let end = toast.createdAt.advanced(by: toast.duration)
    let instants = reduceMotion ? [end] : updateInstants(through: end)
    return TimelineView(.explicit(instants)) { context in
      ToastTimelineContent(
        toast: toast,
        instant: context.instant,
        reduceMotion: context.isReducedMotionEnabled,
        controller: controller
      )
    }.graphBody
  }

  private func updateInstants(through end: TimeInstant) -> [TimeInstant] {
    guard toast.fade > .zero else { return [end] }
    let start = end.advanced(by: .nanoseconds(-toast.fade.nanoseconds))
    return start == end ? [end] : [start, end]
  }
}

extension Toast: SemanticRenderable, View {
  /// Returns the toast size constrained by a proposal.
  /// - Complexity: O(*n*), where *n* is the message length.
  public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
    let width = min(maximumWidth, max(1, proposal.width ?? maximumWidth))
    return CellSize(width: width, height: wrappedLines(width: max(1, width - 2)).count)
  }

  /// Paints the toast and returns its semantic node.
  /// - Complexity: O(*n* + *w* × *h*), where *n* is message length and the other terms are frame dimensions.
  public func paint(
    into surface: inout Surface,
    context: PaintContext,
    resources: inout ControlRenderResources
  ) throws -> SemanticNode {
    let toastFrame = CellRect(origin: context.origin, size: context.frameSize)
    let panelStyle = CellStyle(foreground: .rgba(.white), background: .rgba(RGBA(redByte: 38, greenByte: 40, blueByte: 48)))
    let railColor =
      switch kind {
      case .info: RGBA(redByte: 80, greenByte: 166, blueByte: 255)
      case .success: RGBA(redByte: 70, greenByte: 190, blueByte: 120)
      case .warning: RGBA(redByte: 240, greenByte: 180, blueByte: 60)
      case .error: RGBA(redByte: 235, greenByte: 90, blueByte: 90)
      }
    try surface.clear(toastFrame, with: .makeBlank(styleID: resources.internPaintStyle(panelStyle)))
    _ = try AccentRail(style: CellStyle(foreground: .rgba(railColor), background: panelStyle.background))
      .paint(into: &surface, context: PaintContext(clip: toastFrame, origin: toastFrame.origin), resources: &resources)
    let textContext = PaintContext(clip: toastFrame.inset(by: EdgeInsets(leading: 2)), origin: toastFrame.origin.offsetBy(dx: 2))
    _ = try Text(wrappedLines(width: max(1, toastFrame.width - 2)).joined(separator: "\n"), style: panelStyle)
      .paint(into: &surface, context: textContext, resources: &resources)
    return semanticNode(frame: toastFrame)
  }

  /// The primitive node descriptor for the toast.
  @MainActor
  public var graphBody: [NodeDescriptor] {
    [NodeDescriptor(type: Self.self, primitive: self, hitTest: HitTestMetadata(zIndex: 1000), dirtyOnUpdate: .layout)]
  }
}
