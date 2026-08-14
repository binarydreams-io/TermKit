/// A value that exposes data that the animation system can interpolate.
public protocol Animatable {
    /// The vector type that represents the animatable state.
    associatedtype AnimatableData: VectorArithmetic

    /// The data that represents the value's animatable state.
    var animatableData: AnimatableData { get set }
}

/// A modifier whose output can change as its animatable data changes.
public protocol AnimatableModifier: Animatable {
    /// The input content type.
    associatedtype Content
    /// The output content type.
    associatedtype Body

    /// Creates the modified output for the specified content.
    @MainActor func body(content: Content) -> Body
}

@MainActor
private final class AnimatableModifierBox<Modifier: AnimatableModifier> {
    var modifier: Modifier

    init(_ modifier: Modifier) {
        self.modifier = modifier
    }
}

private struct AnimatableModifierBody<Modifier: AnimatableModifier>: View
where Modifier.Content: View, Modifier.Body: View {
    let content: Modifier.Content
    let box: AnimatableModifierBox<Modifier>

    var graphBody: [NodeDescriptor] {
        box.modifier.body(content: content).graphBody
    }
}

private struct AnimatableModifierAttribute<Modifier: AnimatableModifier>: MountedStructureSamplingAttribute {
    let target: Modifier.AnimatableData
    let transaction: Transaction

    var id: AnyHashable { ObjectIdentifier(Modifier.self) }
    var stagedDirtyFlags: DirtyFlags { .structure }

    func apply(
        to node: MountedNode,
        replacing previous: (any MountedNodeAttribute)?
    ) -> [MountedNodeAttributeAction] {
        let property = property(for: node)
        return AnimatablePropertyAttribute(
            property: property,
            value: target,
            transaction: transaction
        ).apply(
            to: node,
            replacing: (previous as? Self).map {
                AnimatablePropertyAttribute(property: property, value: $0.target, transaction: $0.transaction)
            }
        )
    }

    func remove(from node: MountedNode) -> [MountedNodeAttributeAction] {
        AnimatablePropertyAttribute(
            property: property(for: node),
            value: target,
            transaction: transaction
        ).remove(from: node)
    }

    func sample(on node: MountedNode, at instant: TimeInstant) -> MountedNodeAttributeSample {
        AnimatablePropertyAttribute(
            property: property(for: node),
            value: target,
            transaction: transaction
        ).sample(on: node, at: instant)
    }

    func requiresStructureSampling(on node: MountedNode, at instant: TimeInstant) -> Bool {
        node.animationStatus(for: property(for: node)) == .running
    }

    private func property(for node: MountedNode) -> PresentationProperty<Modifier.AnimatableData> {
        PresentationProperty(
            key: AnimationPropertyKey(rawValue: "modifier.\(String(reflecting: Modifier.self))"),
            dirtyFlags: .paint
        )
    }
}

private struct AnimatableModifiedView<Content: View, Modifier: AnimatableModifier>: View
where Modifier.Content == Content, Modifier.Body: View {
    let content: Content
    let modifier: Modifier

    var graphBody: [NodeDescriptor] {
        let box = AnimatableModifierBox(modifier)
        let attribute = AnimatableModifierAttribute<Modifier>(
            target: modifier.animatableData,
            transaction: .current
        )
        let descriptor = NodeDescriptor.makeDeclarative(AnimatableModifierBody(content: content, box: box))
            .attribute(attribute)
            .scopedExpansion { node, body in
                if let node {
                    let property = PresentationProperty<Modifier.AnimatableData>(
                        key: AnimationPropertyKey(rawValue: "modifier.\(String(reflecting: Modifier.self))"),
                        dirtyFlags: .paint
                    )
                    if let value = node.previewPresentationValue(property, at: Transaction.current.animationTime) {
                        box.modifier.animatableData = value
                    }
                }
                return try body()
            }
        return [descriptor]
    }
}

extension View {
    /// Applies an animatable modifier to this view.
    /// - Complexity: O(1).
    public func modifier<Modifier: AnimatableModifier>(_ modifier: Modifier) -> some View
    where Modifier.Content == Self, Modifier.Body: View {
        AnimatableModifiedView(content: self, modifier: modifier)
    }
}

extension MountedNode {
    fileprivate func previewPresentationValue<Value: VectorArithmetic>(
        _ property: PresentationProperty<Value>,
        at instant: TimeInstant
    ) -> Value? {
        previewPresentationValue(for: property, at: instant)
    }
}

extension Animatable where AnimatableData == EmptyAnimatableData {
    /// The empty animatable state.
    public var animatableData: EmptyAnimatableData {
        get { .zero }
        set {}
    }
}
