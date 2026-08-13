import TUIFoundation
import TUIViewGraph

public enum LayoutPrimitive: Sendable, Hashable {
    case stack(StackLayout)
    case padding(PaddingLayout)
    case frame(FrameLayout)
    case scrollViewport(ScrollViewportLayout)
}

public struct ScrollViewportLayout: Sendable, Hashable {
    public var width: Int?
    public var height: Int?

    public init(width: Int? = nil, height: Int? = nil) {
        precondition(width.map { $0 >= 0 } ?? true)
        precondition(height.map { $0 >= 0 } ?? true)
        self.width = width
        self.height = height
    }
}

public struct ScrollViewport: View {
    private let descriptor: NodeDescriptor

    @MainActor
    public init(
        width: Int? = nil,
        height: Int? = nil,
        @ViewBuilder content: () -> [NodeDescriptor]
    ) {
        let primitive = LayoutPrimitive.scrollViewport(ScrollViewportLayout(width: width, height: height))
        descriptor = NodeDescriptor(
            type: Self.self,
            value: primitive,
            primitive: primitive,
            children: buildViewGraph(content),
            dirtyOnUpdate: .layout
        )
    }

    @MainActor
    public var graphBody: [NodeDescriptor] { [descriptor] }
}

public struct VStack: View {
    private let descriptor: NodeDescriptor

    @MainActor
    public init(
        alignment: HorizontalCellAlignment = .center,
        spacing: Int = 0,
        @ViewBuilder content: () -> [NodeDescriptor]
    ) {
        let primitive = LayoutPrimitive.stack(
            StackLayout(axis: .vertical, spacing: spacing, horizontalAlignment: alignment)
        )
        descriptor = NodeDescriptor(
            type: Self.self,
            value: primitive,
            primitive: primitive,
            children: buildViewGraph(content),
            dirtyOnUpdate: .layout
        )
    }

    @MainActor
    public var graphBody: [NodeDescriptor] {
        [descriptor]
    }
}

public struct HStack: View {
    private let descriptor: NodeDescriptor

    @MainActor
    public init(
        alignment: VerticalCellAlignment = .center,
        spacing: Int = 0,
        @ViewBuilder content: () -> [NodeDescriptor]
    ) {
        let primitive = LayoutPrimitive.stack(
            StackLayout(axis: .horizontal, spacing: spacing, verticalAlignment: alignment)
        )
        descriptor = NodeDescriptor(
            type: Self.self,
            value: primitive,
            primitive: primitive,
            children: buildViewGraph(content),
            dirtyOnUpdate: .layout
        )
    }

    @MainActor
    public var graphBody: [NodeDescriptor] {
        [descriptor]
    }
}

public extension View {
    func padding(_ insets: EdgeInsets) -> some View {
        LayoutModifierView(content: self, primitive: .padding(PaddingLayout(insets)))
    }

    func padding(_ amount: Int = 1) -> some View {
        padding(EdgeInsets(all: amount))
    }

    func frame(
        width: Int? = nil,
        height: Int? = nil,
        alignment: CellAlignment = .center
    ) -> some View {
        LayoutModifierView(
            content: self,
            primitive: .frame(FrameLayout(width: width, height: height, alignment: alignment))
        )
    }

    func scrollViewport(width: Int? = nil, height: Int? = nil) -> some View {
        LayoutModifierView(
            content: self,
            primitive: .scrollViewport(ScrollViewportLayout(width: width, height: height))
        )
    }
}

private struct LayoutModifierView<Content: View>: View {
    private let descriptor: NodeDescriptor

    @MainActor
    init(content: Content, primitive: LayoutPrimitive) {
        descriptor = NodeDescriptor(
            type: Self.self,
            value: primitive,
            primitive: primitive,
            children: buildViewGraph { content },
            dirtyOnUpdate: .layout
        )
    }

    @MainActor
    var graphBody: [NodeDescriptor] {
        [descriptor]
    }
}
