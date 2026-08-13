import TUIAnimation
import TUIControls
import TUIFoundation
import TUILayout
import TUIRenderer
import TUIViewGraph

public typealias DesignOverlayHost<Content: Sendable> = TUIControls.OverlayHost<Content>

public enum DialogWidth: Int, CaseIterable, Sendable, Hashable {
    case compact = 60
    case regular = 88
    case wide = 116
}

extension DialogSurface: SemanticRenderable, TUIViewGraph.View where Content == String {
    nonisolated public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        CellSize(width: max(0, proposal.width ?? preferredWidth.rawValue), height: max(0, proposal.height ?? 3))
    }

    nonisolated public func paint(
        into surface: inout TUIRenderer.Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let backdrop = CellStyle(background: .rgba(RGBA.black.applyingOpacity(0.45)))
        let backdropID = try resources.internPaintStyle(backdrop)
        surface.clear(context.clip, with: .blank(styleID: backdropID))
        let panel = frame(in: context.clip.size, contentHeight: min(context.clip.height, 3))
            .offsetBy(dx: context.origin.x, dy: context.origin.y)
        let panelStyle = CellStyle(foreground: .rgba(.white), background: .rgba(RGBA(redByte: 38, greenByte: 40, blueByte: 48)))
        let panelID = try resources.internPaintStyle(panelStyle)
        surface.clear(panel, with: .blank(styleID: panelID))
        let textContext = PaintContext(origin: panel.origin.offsetBy(dx: 2, dy: 1), clip: panel.inset(by: EdgeInsets(horizontal: 2, vertical: 1)))
        let child = try Text(content, style: panelStyle).paint(into: &surface, context: textContext, resources: &resources)
        return semanticNode(frame: panel, children: [child])
    }

    @MainActor
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(
            type: Self.self,
            primitive: self,
            focus: FocusMetadata(isFocusable: true),
            hitTest: HitTestMetadata(isEnabled: true, zIndex: 100, disablesDescendants: false, modalScope: id.rawValue),
            dirtyOnUpdate: .layout
        )]
    }
}

public struct DialogSurface<Content: Sendable>: Sendable {
    public var id: OverlayID
    public var title: String
    public var preferredWidth: DialogWidth
    public var horizontalMargin: Int
    public var content: Content

    public init(
        id: OverlayID,
        title: String,
        preferredWidth: DialogWidth = .regular,
        horizontalMargin: Int = 2,
        content: Content
    ) {
        self.id = id
        self.title = title
        self.preferredWidth = preferredWidth
        self.horizontalMargin = max(0, horizontalMargin)
        self.content = content
    }

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

    public func presentation(zIndex: Int = 100) -> OverlayPresentation<DialogSurface<Content>> {
        OverlayPresentation(
            id: id,
            kind: .dialog,
            content: self,
            isModal: true,
            dismissOnEscape: true,
            zIndex: zIndex
        )
    }

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

public enum ToastKind: Sendable, Hashable {
    case info
    case success
    case warning
    case error
}

public struct Toast: Sendable, Hashable {
    public var id: OverlayID
    public var message: String
    public var kind: ToastKind
    public var maximumWidth: Int
    public var createdAt: TimeInstant
    public var duration: TUIDuration
    public var fade: TUIDuration

    public init(
        id: OverlayID,
        message: String,
        kind: ToastKind = .info,
        maximumWidth: Int = 44,
        createdAt: TimeInstant,
        duration: TUIDuration = .seconds(4),
        fade: TUIDuration = .milliseconds(160)
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

    public func opacity(at instant: TimeInstant, reduceMotion: Bool) -> Double {
        guard instant >= createdAt else { return 0 }
        guard reduceMotion == false else { return instant < createdAt.advanced(by: duration) ? 1 : 0 }
        let end = createdAt.advanced(by: duration)
        if instant >= end { return 0 }
        guard fade > .zero else { return 1 }
        let remaining = instant.duration(to: end)
        return remaining >= fade ? 1 : max(0, remaining.seconds / fade.seconds)
    }

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
        if current.isEmpty == false { lines.append(current) }
        return lines.isEmpty ? [""] : lines
    }

    public func presentation(zIndex: Int = 1_000) -> OverlayPresentation<Toast> {
        OverlayPresentation(id: id, kind: .toast, content: self, zIndex: zIndex)
    }

    @MainActor
    public func timeline(
        onExpire: @escaping @MainActor @Sendable (OverlayID) -> Void
    ) -> ToastTimelineView {
        ToastTimelineView(toast: self, onExpire: onExpire)
    }

    public func semanticNode(frame: CellRect? = nil) -> SemanticNode {
        SemanticNode(id: SemanticID(rawValue: "toast-\(id.rawValue)"), role: .status, label: message, frame: frame)
    }
}

@MainActor
private final class ToastExpirationController: @unchecked Sendable {
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
        [NodeDescriptor(
            type: Self.self,
            lifecycle: NodeLifecycle(
                onMount: { _ in controller.expire() },
                onUpdate: { _ in controller.expire() }
            )
        )]
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

public struct ToastTimelineView: View {
    public let toast: Toast
    @Environment(ReduceMotionEnvironmentKey.self) private var reduceMotion
    private let controller: ToastExpirationController

    public init(
        toast: Toast,
        onExpire: @escaping @MainActor @Sendable (OverlayID) -> Void
    ) {
        self.toast = toast
        controller = ToastExpirationController { onExpire(toast.id) }
    }

    public var graphBody: [NodeDescriptor] {
        let end = toast.createdAt.advanced(by: toast.duration)
        let instants = reduceMotion ? [end] : updateInstants(through: end)
        return TimelineView(.explicit(instants)) { context in
            ToastTimelineContent(
                toast: toast,
                instant: context.instant,
                reduceMotion: context.reduceMotion,
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

extension Toast: SemanticRenderable, TUIViewGraph.View {
    nonisolated public func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        let width = min(maximumWidth, max(1, proposal.width ?? maximumWidth))
        return CellSize(width: width, height: wrappedLines(width: max(1, width - 2)).count)
    }

    nonisolated public func paint(
        into surface: inout TUIRenderer.Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let localFrame = frame(in: context.clip.size)
        let toastFrame = localFrame.offsetBy(dx: context.origin.x, dy: context.origin.y)
        let panelStyle = CellStyle(foreground: .rgba(.white), background: .rgba(RGBA(redByte: 38, greenByte: 40, blueByte: 48)))
        let railColor: RGBA = switch kind {
        case .info: RGBA(redByte: 80, greenByte: 166, blueByte: 255)
        case .success: RGBA(redByte: 70, greenByte: 190, blueByte: 120)
        case .warning: RGBA(redByte: 240, greenByte: 180, blueByte: 60)
        case .error: RGBA(redByte: 235, greenByte: 90, blueByte: 90)
        }
        surface.clear(toastFrame, with: .blank(styleID: try resources.internPaintStyle(panelStyle)))
        _ = try AccentRail(style: CellStyle(foreground: .rgba(railColor), background: panelStyle.background))
            .paint(into: &surface, context: PaintContext(origin: toastFrame.origin, clip: toastFrame), resources: &resources)
        let textContext = PaintContext(origin: toastFrame.origin.offsetBy(dx: 2), clip: toastFrame.inset(by: EdgeInsets(leading: 2)))
        _ = try Text(wrappedLines(width: max(1, toastFrame.width - 2)).joined(separator: "\n"), style: panelStyle)
            .paint(into: &surface, context: textContext, resources: &resources)
        return semanticNode(frame: toastFrame)
    }

    @MainActor
    public var graphBody: [NodeDescriptor] {
        [NodeDescriptor(type: Self.self, primitive: self, hitTest: HitTestMetadata(zIndex: 1_000), dirtyOnUpdate: .layout)]
    }
}
