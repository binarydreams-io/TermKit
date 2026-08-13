# Animation

Use ``withAnimation(_:completion:_:)`` for a state mutation. Use `animation(_:value:)` to watch one value. Mounted tracks retarget from their current presentation value.

```swift
import SwiftTUI

let view = Text("Saving")
    .foregroundColor(.white)
    .opacity(0.8)
    .offset(x: 2, y: 0)
    .animation(.easeInOut(duration: .milliseconds(180)), value: true)
```

Typed modifiers support color, border, opacity, offset, frame dimensions, padding, spacing, clipping, reveal, highlights, and scroll position. ``AnyTransition`` supports insertion and removal effects.

Use ``TimelineView`` for animation, periodic, or explicit schedules. Timeline demand uses the shared ``FrameScheduler`` and creates no private timer. An explicit schedule becomes idle after its final entry.

Reduced motion resolves spatial presentation to a stable final state. Disabled animation applies target values immediately.
