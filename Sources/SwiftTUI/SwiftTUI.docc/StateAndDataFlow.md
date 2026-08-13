# State And Data Flow

Use ``State`` for state that a mounted view owns. Use ``Binding`` when a child must update state from another view.

```swift
import SwiftTUI

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

State remains attached while structural identity matches. A different type, branch, or explicit key creates a new state location. Environment and preference dependencies let the graph invalidate only dependent branches.

Do not mutate state while the runtime evaluates `graphBody`. The graph reports a typed diagnostic for this error.
