# State and Data Flow

Learn how TermKit stores view state and shares data between views.

Use ``State`` for data that a mounted view owns. Use ``Binding`` when a child must read and update data owned elsewhere.

```swift
import TermKit

struct CounterView: View {
    @State private var count = 0

    var graphBody: [NodeDescriptor] {
        VStack {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
        }.graphBody
    }
}
```

State remains attached while the view's structural identity matches. A different type, branch, position, or explicit key creates a new state location.

Environment and preference reads register dependencies. The graph then invalidates only the branches that depend on changed values.

Do not mutate state while TermKit evaluates `graphBody`. The graph reports ``BodyMutationDiagnostic`` for this error.
