//  TUIkit - Terminal UI Kit for Swift
//  MouseInteractionModifier.swift
//
//  License: MIT

/// A modifier that registers the rendered bounds for mouse interaction.
public struct MouseInteractionModifier<Content: View>: View {
    enum ClickBehavior {
        case action(() -> Void)
        case key(Key)
    }

    let content: Content
    let click: ClickBehavior?
    let scroll: ((MouseEvent.ScrollDirection) -> Void)?

    public var body: Never {
        fatalError("MouseInteractionModifier renders via Renderable")
    }
}

extension MouseInteractionModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let contentContext = context.withIdentityScope("mouseInteraction.content")
        var buffer = TUIkit.renderToBuffer(content, context: contentContext)
        guard context.isMeasuring == false,
            buffer.width > 0,
            buffer.height > 0,
            let dispatcher = context.environment.interactionDispatcher
        else {
            return buffer
        }

        let id = "interaction-\(context.identity.path)"
        if let click {
            switch click {
            case .action(let action):
                dispatcher.registerClick(id: id, action: action)
            case .key(let key):
                dispatcher.registerClick(id: id, key: key)
            }
        }
        if let scroll {
            dispatcher.registerScroll(id: id, action: scroll)
        }

        buffer.regions.append(
            InteractionRegion(
                id: id,
                rect: TerminalCellRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
            )
        )
        return buffer
    }
}
