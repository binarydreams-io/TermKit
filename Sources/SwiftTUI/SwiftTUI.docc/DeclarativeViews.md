# Declarative Views

Declare terminal content with ``View`` values. A view returns descriptors from `graphBody`. The runtime retains mounted nodes between frames.

```swift
import SwiftTUI

struct StatusView: View {
    let message: String

    var graphBody: [NodeDescriptor] {
        VStack(alignment: .leading, spacing: 1) {
            Text("Build")
            Text(message)
        }
        .padding(1)
        .frame(width: 40, alignment: .topLeading)
        .graphBody
    }
}
```

Use ``VStack`` and ``HStack`` for ordered layout. Use `padding`, `frame`, and `scrollViewport` for retained layout wrappers. Structural position and explicit keys determine identity.

The runtime applies the narrowest invalidation level. Paint changes skip reconciliation and layout. Layout changes preserve the mounted tree. Structure changes reevaluate `graphBody` and reconcile children.
