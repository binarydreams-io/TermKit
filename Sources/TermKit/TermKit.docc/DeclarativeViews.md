# Declarative Views

Compose terminal interfaces from views that produce retained graph nodes.

Declare terminal content with values that conform to ``View``. Each view provides node descriptors through `graphBody`.

```swift
import TermKit

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

Use ``VStack`` and ``HStack`` for ordered layout. The `padding`, `frame`, and `scrollViewport` modifiers add retained layout nodes.

The runtime retains mounted nodes between frames. A node's type, structural position, branch, and explicit key determine its identity.

TermKit applies the narrowest required update. Paint changes skip layout, layout changes preserve the mounted tree, and structural changes reevaluate `graphBody`.
