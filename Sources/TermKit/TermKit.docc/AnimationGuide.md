# Animation

Add state-driven motion and scheduled updates to declarative views.

Use ``withAnimation(_:completion:_:)`` to animate state changes. Use `animation(_:value:)` to animate changes to one observed value.

```swift
import TermKit

let view = Text("Saving")
    .foregroundColor(.white)
    .opacity(0.8)
    .offset(x: 2, y: 0)
    .animation(.easeInOut(duration: .milliseconds(180)), value: true)
```

When a target changes during an animation, TermKit starts the new track from the current presented value.

Animation modifiers cover color, borders, opacity, offsets, dimensions, padding, spacing, clipping, highlights, and scroll position. ``AnyTransition`` defines insertion and removal effects.

Use ``TimelineView`` for animation, periodic, or explicit schedules. It requests frames from the shared ``FrameScheduler`` instead of creating a timer.

An explicit schedule becomes idle after its last entry. Reduced motion removes spatial movement, and disabled animation applies target values immediately.
