import Foundation
import TermKit

struct PlayerQueueView: View, SemanticRenderable, ControlInputHandler, ControlPointerActivatable {
    let model: PlayerModel
    let visibleRowCount: Int

    var graphBody: [NodeDescriptor] {
        [
            NodeDescriptor(
                type: Self.self,
                primitive: self,
                focus: FocusMetadata(isFocusable: true),
                hitTest: HitTestMetadata(isEnabled: true),
                dirtyOnUpdate: .layout
            )
        ]
    }

    func sizeThatFits(_ proposal: ProposedCellSize) -> CellSize {
        CellSize(width: proposal.width ?? 40, height: min(visibleRowCount, proposal.height ?? visibleRowCount))
    }

    func paint(
        into surface: inout Surface,
        context: PaintContext,
        resources: inout ControlRenderResources
    ) throws -> SemanticNode {
        let count = min(model.tracks.count, min(visibleRowCount, context.frameSize.height))
        var children: [SemanticNode] = []
        for index in 0..<count {
            let track = model.tracks[index]
            let selected = index == model.selectedTrackIndex
            let current = index == model.currentTrackIndex
            let marker = current ? "▶" : selected ? "◆" : " "
            let duration = formatTime(track.duration)
            let availableTitle = max(0, context.frameSize.width - duration.count - 5)
            let title = String(track.title.prefix(availableTitle))
            let padding = String(repeating: " ", count: max(1, availableTitle - title.count + 1))
            let text = "\(marker) \(title)\(padding)\(duration)"
            let style = selected ? PlayerStyles.selected : current ? PlayerStyles.current : PlayerStyles.body
            let origin = context.origin.offsetBy(dx: 0, dy: index)
            let rowFrame = CellRect(origin: origin, size: CellSize(width: context.frameSize.width, height: 1))
            let rowContext = PaintContext(
                clip: context.clip.intersection(rowFrame) ?? .zero,
                origin: origin,
                frameSize: rowFrame.size
            )
            _ = try SurfaceView(
                text: text,
                foreground: resolvedForeground(style),
                background: resolvedBackground(style),
                id: SemanticID(rawValue: "queue-row-surface-\(index)")
            ).paint(into: &surface, context: rowContext, resources: &resources)
            var state: SemanticState = []
            if selected { state.insert(.selected) }
            if current { state.insert(.current) }
            children.append(
                SemanticNode(
                    id: SemanticID(rawValue: "queue-item-\(index)"),
                    role: .listItem,
                    label: "\(track.title) by \(track.artist)",
                    value: duration,
                    state: state,
                    actions: [.activate, .focus],
                    frame: rowFrame
                )
            )
        }
        return SemanticNode(
            id: "player-queue",
            role: .list,
            label: "Playback queue",
            frame: CellRect(origin: context.origin, size: context.frameSize),
            children: children
        )
    }

    func handleControlInput(_ event: ControlInputEvent) -> Bool {
        switch event {
        case .moveUp:
            model.moveSelection(by: -1)
        case .moveDown:
            model.moveSelection(by: 1)
        case .submit:
            model.playSelectedTrack()
        default:
            return false
        }
        return true
    }

    func activate(at point: CellPoint) -> Bool {
        guard point.y >= 0, point.y < min(model.tracks.count, visibleRowCount) else { return false }
        model.selectTrack(at: point.y, startsPlaying: true)
        return true
    }

    private func resolvedForeground(_ style: CellStyle) -> RGBA {
        guard case .rgba(let color)? = style.foreground else { return PlayerStyles.light }
        return color
    }

    private func resolvedBackground(_ style: CellStyle) -> RGBA {
        guard case .rgba(let color)? = style.background else { return PlayerStyles.panel }
        return color
    }
}

func formatTime(_ duration: TimeSpan) -> String {
    let seconds = max(0, Int(duration.seconds.rounded(.down)))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}
