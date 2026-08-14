private enum AnimationTriggerMetadata: NodeMetadataKey {
    typealias Value = AnyHashable
}

private enum AnimationTrackStoreMetadata: NodeMetadataKey {
    typealias Value = AnimationTrackStore
}

private enum TransitionAttributeID {}

private enum TransitionMetadata: NodeMetadataKey {
    typealias Value = AnyTransition
}

private let transitionProgressProperty = PresentationProperties.transitionVisibility.key

struct AnimatablePropertyAttribute<Value: VectorArithmetic>: MountedNodeAttribute {
    let property: PresentationProperty<Value>
    let value: Value
    let transaction: Transaction

    var id: AnyHashable { property.key }
    var stagedDirtyFlags: DirtyFlags { property.dirtyFlags }

    func apply(
        to node: MountedNode,
        replacing previous: (any MountedNodeAttribute)?
    ) -> [MountedNodeAttributeAction] {
        let store = node.metadata(for: AnimationTrackStoreMetadata.self) ?? AnimationTrackStore()
        node.setMetadata(store, for: AnimationTrackStoreMetadata.self)
        let oldValue = (previous as? Self)?.value ?? value
        guard previous == nil || oldValue != value else { return [] }
        var propertyTransaction = transaction
        if transaction.isReducedMotionEnabled, property.dirtyFlags.contains(.layout) {
            propertyTransaction.animation = nil
        }
        let result = store.setTargetDeferringActions(
            value,
            from: oldValue,
            for: AnimationTrackKey(nodeID: node.id, property: property.key),
            at: propertyTransaction.animationTime,
            transaction: propertyTransaction
        )
        return result.actions
    }

    func remove(from node: MountedNode) -> [MountedNodeAttributeAction] {
        let key = AnimationTrackKey(nodeID: node.id, property: property.key)
        guard let store = node.metadata(for: AnimationTrackStoreMetadata.self) else { return [] }
        return store.removeDeferringCompletion(key).map { [$0] } ?? []
    }

    func sample(on node: MountedNode, at instant: TimeInstant) -> MountedNodeAttributeSample {
        let key = AnimationTrackKey(nodeID: node.id, property: property.key)
        guard let store = node.metadata(for: AnimationTrackStoreMetadata.self) else { return .inactive }
        let wasRunning = store.status(for: key) == .running
        let result = store.sampleDeferringCompletion(key, as: Value.self, at: instant)
        return MountedNodeAttributeSample(
            isActive: store.status(for: key) == .running,
            dirtyFlags: wasRunning ? property.dirtyFlags : [],
            completionActions: result.completion.map { [$0] } ?? []
        )
    }
}

private struct TransitionAttribute: MountedNodeAttribute {
    let transition: AnyTransition
    let transaction: Transaction

    var id: AnyHashable { ObjectIdentifier(TransitionAttributeID.self) }

    func apply(
        to node: MountedNode,
        replacing previous: (any MountedNodeAttribute)?
    ) -> [MountedNodeAttributeAction] {
        let resolved = node.metadata(for: TransitionMetadata.self) ?? transition.resolved(for: transaction)
        node.setMetadata(resolved, for: TransitionMetadata.self)
        guard previous == nil || node.presentationPhase == .active else { return [] }
        guard resolved.insertionEffects.isEmpty == false else { return [] }
        let token = node.beginPresentationTransition(.inserting)
        let store = node.metadata(for: AnimationTrackStoreMetadata.self) ?? AnimationTrackStore()
        node.setMetadata(store, for: AnimationTrackStoreMetadata.self)
        var transaction = transaction
        transaction.completion = { [weak node] in
            node?.completePresentationTransition(token)
        }
        let result = store.setTargetDeferringActions(
            1.0,
            from: 0.0,
            for: AnimationTrackKey(nodeID: node.id, property: transitionProgressProperty),
            at: transaction.animationTime,
            transaction: transaction
        )
        return result.actions
    }

    func remove(from node: MountedNode) -> [MountedNodeAttributeAction] {
        var transaction = Transaction.current
        let resolved = transition.resolved(for: transaction)
        node.setMetadata(resolved, for: TransitionMetadata.self)
        let token = node.currentPresentationTransitionToken
        guard resolved.removalEffects.isEmpty == false else {
            return [{ [weak node] in node?.completePresentationTransition(token) }]
        }
        let store = node.metadata(for: AnimationTrackStoreMetadata.self) ?? AnimationTrackStore()
        node.setMetadata(store, for: AnimationTrackStoreMetadata.self)
        transaction.completion = { [weak node] in
            node?.completePresentationTransition(token)
        }
        let result = store.setTargetDeferringActions(
            0.0,
            from: 1.0,
            for: AnimationTrackKey(nodeID: node.id, property: transitionProgressProperty),
            at: transaction.animationTime,
            transaction: transaction
        )
        return result.actions
    }

    func sample(on node: MountedNode, at instant: TimeInstant) -> MountedNodeAttributeSample {
        let wasRunning = node.animationStatus(for: transitionProgressProperty) == .running
        let result = node.transitionPresentationSampleDeferringCompletion(at: instant)
        let resolved = transition.resolved(for: transaction)
        let resolvedEffects = resolved.insertionEffects + resolved.removalEffects
        return MountedNodeAttributeSample(
            isActive: node.animationStatus(for: transitionProgressProperty) == .running,
            dirtyFlags: wasRunning ? (resolvedEffects.contains(where: \.isSpatial) ? .layout : .paint) : [],
            completionActions: result.completion.map { [$0] } ?? []
        )
    }
}

private struct AnimationScopedView<Content: View, Value: Hashable & Sendable>: View {
    let content: Content
    let animation: Animation?
    let value: Value

    var graphBody: [NodeDescriptor] {
        var descriptor = NodeDescriptor.makeDeclarative(content)
        let trigger = AnyHashable(value)
        descriptor.lifecycle.onMount = { node in
            node.setMetadata(trigger, for: AnimationTriggerMetadata.self)
        }
        descriptor.lifecycle.onUpdate = { node in
            node.setMetadata(trigger, for: AnimationTriggerMetadata.self)
        }
        descriptor = descriptor.scopedExpansion { node, body in
            var transaction = Transaction.current
            if let node, node.metadata(for: AnimationTriggerMetadata.self) != trigger {
                transaction.animation = transaction.areAnimationsEnabled ? animation : nil
            }
            return try withTransaction(transaction, body)
        }
        return [descriptor]
    }
}

private struct PresentationPropertyView<Content: View, Value: VectorArithmetic>: View {
    let content: Content
    let property: PresentationProperty<Value>
    let value: Value

    var graphBody: [NodeDescriptor] {
        let descriptor = NodeDescriptor.makeDeclarative(content).scopedExpansion { _, body in
            try body().presentationValue(value, for: property)
        }
        return [descriptor]
    }
}

extension View {
    /// Applies an animation when the specified value changes.
    /// - Complexity: O(1).
    public func animation<Value: Hashable & Sendable>(_ animation: Animation?, value: Value) -> some View {
        AnimationScopedView(content: self, animation: animation, value: value)
    }

    /// Sets the animatable foreground color.
    /// - Complexity: O(1).
    public func foregroundColor(_ color: RGBA) -> some View {
        presentationProperty(.foregroundColor, value: LinearRGBA(color))
    }

    /// Sets the animatable background color.
    /// - Complexity: O(1).
    public func backgroundColor(_ color: RGBA) -> some View {
        presentationProperty(.backgroundColor, value: LinearRGBA(color))
    }

    /// Sets the animatable border color.
    /// - Complexity: O(1).
    public func borderColor(_ color: RGBA) -> some View {
        presentationProperty(.borderColor, value: LinearRGBA(color))
    }

    /// Sets the animatable opacity target.
    /// - Complexity: O(1).
    public func opacity(_ opacity: Double) -> some View {
        presentationProperty(.opacity, value: opacity)
    }

    /// Sets the animatable cell offset target.
    /// - Complexity: O(1).
    public func offset(x: Double = 0, y: Double = 0) -> some View {
        offset(CellVector(x: x, y: y))
    }

    /// Sets the animatable cell offset target.
    /// - Complexity: O(1).
    public func offset(_ offset: CellVector) -> some View {
        presentationProperty(.offset, value: offset)
    }

    /// Sets the animatable frame width and height targets.
    /// - Complexity: O(1).
    public func animatedFrame(width: Double, height: Double) -> some View {
        presentationProperty(.frameWidth, value: width)
            .presentationProperty(.frameHeight, value: height)
    }

    /// Sets the animatable padding target.
    /// - Complexity: O(1).
    public func animatedPadding(_ insets: FloatingEdgeInsets) -> some View {
        presentationProperty(.padding, value: insets)
    }

    /// Sets the animatable spacing target.
    /// - Complexity: O(1).
    public func animatedSpacing(_ spacing: Double) -> some View {
        presentationProperty(.spacing, value: spacing)
    }

    /// Sets the animatable clip inset target.
    /// - Complexity: O(1).
    public func clipInsets(_ insets: FloatingEdgeInsets) -> some View {
        presentationProperty(.clipInsets, value: insets)
    }

    /// Sets the animatable reveal target.
    /// - Complexity: O(1).
    public func reveal(_ amount: Double) -> some View {
        presentationProperty(.clipReveal, value: amount)
    }

    /// Sets the animatable selection highlight color.
    /// - Complexity: O(1).
    public func selectionHighlight(_ color: RGBA) -> some View {
        presentationProperty(.selectionHighlight, value: LinearRGBA(color))
    }

    /// Sets the animatable focus highlight color.
    /// - Complexity: O(1).
    public func focusHighlight(_ color: RGBA) -> some View {
        presentationProperty(.focusHighlight, value: LinearRGBA(color))
    }

    /// Sets the animatable scroll position target.
    /// - Complexity: O(1).
    public func scrollPosition(x: Double = 0, y: Double = 0) -> some View {
        scrollPosition(CellVector(x: x, y: y))
    }

    /// Sets the animatable scroll position target.
    /// - Complexity: O(1).
    public func scrollPosition(_ position: CellVector) -> some View {
        presentationProperty(.scrollPosition, value: position)
    }

    private func presentationProperty<Value: VectorArithmetic>(
        _ property: PresentationProperty<Value>,
        value: Value
    ) -> some View {
        precondition(
            presentationValueIsFinite(value),
            "Presentation value for '\(property.key.rawValue)' must be finite."
        )
        return PresentationPropertyView(content: self, property: property, value: value)
    }
}

extension NodeDescriptor {
    /// Associates an animatable property value with this node.
    /// - Complexity: O(1).
    @MainActor
    public func animatableValue<Value: VectorArithmetic>(
        _ value: Value,
        for property: AnimationPropertyKey
    ) -> NodeDescriptor {
        presentationValue(value, for: PresentationProperty(key: property, dirtyFlags: .paint))
    }

    /// Associates a typed presentation value with this node.
    /// - Complexity: O(1).
    @MainActor
    public func presentationValue<Value: VectorArithmetic>(
        _ value: Value,
        for property: PresentationProperty<Value>
    ) -> NodeDescriptor {
        precondition(
            presentationValueIsFinite(value),
            "Presentation value for '\(property.key.rawValue)' must be finite."
        )
        return attribute(
            AnimatablePropertyAttribute(
                property: property,
                value: value,
                transaction: Transaction.current
            )
        )
    }

    /// Applies a transition when the graph inserts or removes this node.
    /// - Complexity: O(1).
    @MainActor
    public func transition(_ transition: AnyTransition) -> NodeDescriptor {
        var copy = attribute(
            TransitionAttribute(
                transition: transition,
                transaction: Transaction.current
            )
        )
        copy.removalPolicy = .retainForTransition
        return copy
    }
}

extension MountedNode {
    /// Returns a sampled value without changing the stored track.
    /// - Complexity: O(1) on average.
    public func previewPresentationValue<Value: VectorArithmetic>(
        for property: PresentationProperty<Value>,
        at instant: TimeInstant
    ) -> Value? {
        metadata(for: AnimationTrackStoreMetadata.self)?.preview(
            AnimationTrackKey(nodeID: id, property: property.key),
            as: Value.self,
            at: instant
        )
    }

    /// Returns the target value for a typed presentation property.
    /// - Complexity: O(1) on average.
    public func presentationValue<Value: VectorArithmetic>(_ property: PresentationProperty<Value>) -> Value? {
        presentationTarget(for: property)
    }

    /// Returns the target value for a typed presentation property.
    /// - Complexity: O(1) on average.
    public func presentationValue<Value: VectorArithmetic>(for property: PresentationProperty<Value>) -> Value? {
        presentationTarget(for: property)
    }

    /// Returns the sampled value for a typed presentation property.
    /// - Complexity: O(1) on average.
    public func presentationValue<Value: VectorArithmetic>(
        _ property: PresentationProperty<Value>,
        at instant: TimeInstant
    ) -> Value? {
        presentationValue(for: property.key, as: Value.self, at: instant)
    }

    /// Returns the target value for a typed presentation property.
    /// - Complexity: O(1) on average.
    public func presentationTarget<Value: VectorArithmetic>(for property: PresentationProperty<Value>) -> Value? {
        metadata(for: AnimationTrackStoreMetadata.self)?.target(
            AnimationTrackKey(nodeID: id, property: property.key),
            as: Value.self
        )
    }

    /// Returns the status of the track for a typed presentation property.
    /// - Complexity: O(1) on average.
    public func animationStatus<Value: VectorArithmetic>(for property: PresentationProperty<Value>) -> AnimationTrackStatus? {
        animationStatus(for: property.key)
    }

    /// Returns the sampled presentation value for an animatable property.
    /// - Complexity: O(1) on average.
    public func presentationValue<Value: VectorArithmetic>(
        for property: AnimationPropertyKey,
        as type: Value.Type = Value.self,
        at instant: TimeInstant
    ) -> Value? {
        metadata(for: AnimationTrackStoreMetadata.self)?.sample(
            AnimationTrackKey(nodeID: id, property: property),
            as: type,
            at: instant
        )
    }

    /// Returns the status of the track for an animatable property.
    /// - Complexity: O(1) on average.
    public func animationStatus(for property: AnimationPropertyKey) -> AnimationTrackStatus? {
        metadata(for: AnimationTrackStoreMetadata.self)?.status(
            for: AnimationTrackKey(nodeID: id, property: property)
        )
    }

    /// Returns the sampled insertion or removal transition state.
    /// - Complexity: O(n), where n is the transition effect count.
    public func transitionPresentationSample(at instant: TimeInstant) -> TransitionSample? {
        let result = transitionPresentationSampleDeferringCompletion(at: instant)
        result.completion?()
        return result.sample
    }

    fileprivate func transitionPresentationSampleDeferringCompletion(
        at instant: TimeInstant
    ) -> (sample: TransitionSample?, completion: AnimationCompletion?) {
        let sampledPhase = presentationPhase
        guard sampledPhase != .active,
            let transition = metadata(for: TransitionMetadata.self)
        else { return (nil, nil) }
        let result: (value: Double?, completion: AnimationCompletion?) =
            metadata(
                for: AnimationTrackStoreMetadata.self
            )?.sampleDeferringCompletion(
                AnimationTrackKey(nodeID: id, property: transitionProgressProperty),
                as: Double.self,
                at: instant
            ) ?? (nil, nil)
        guard let visibility = result.value else { return (nil, result.completion) }
        let sample: TransitionSample
        switch sampledPhase {
        case .inserting:
            sample = transition.sample(phase: .insertion, progress: visibility)
        case .removing:
            sample = transition.sample(phase: .removal, progress: 1 - visibility)
        case .active:
            return (nil, result.completion)
        }
        return (sample, result.completion)
    }

    /// Returns the sampled removal transition state.
    /// - Complexity: O(n), where n is the transition effect count.
    public func removalTransitionSample(at instant: TimeInstant) -> TransitionSample? {
        guard presentationPhase == .removing else { return nil }
        return transitionPresentationSample(at: instant)
    }
}
