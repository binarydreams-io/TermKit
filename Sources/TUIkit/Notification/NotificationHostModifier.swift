//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NotificationHostModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Notification Host Modifier

/// A modifier that renders all active notifications from the ``NotificationService``
/// as a stacked overlay.
///
/// Attach this modifier once at the root of your view tree. It reads the
/// active notification entries from the environment's ``NotificationService``,
/// renders each one as a bordered ``Box``, and stacks them vertically in the
/// top-right corner.
///
/// ## Example
///
/// ```swift
/// ContentView()
///     .notificationHost()
/// ```
///
/// The base content remains fully interactive — notifications do not dim
/// or block the background.
///
/// - SeeAlso: ``NotificationService``, ``View/notificationHost(width:surface:)``
struct NotificationHostModifier<Content: View>: View {
    /// The base content to render.
    let content: Content

    /// The fixed width of each notification box in characters.
    let width: Int

    /// How each notification is painted.
    var surface: NotificationSurface = .bordered

    var body: Never {
        fatalError("NotificationHostModifier renders via Renderable")
    }
}

// MARK: - Renderable

extension NotificationHostModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let baseBuffer = TUIkit.renderToBuffer(content, context: context)
        let service = context.environment.notificationService
        let activeEntries = service.activeEntries()

        guard !activeEntries.isEmpty else {
            return baseBuffer
        }

        // Start the animation invalidation task if not already running.
        startAnimationTask(
            entries: activeEntries,
            lifecycle: context.environment.lifecycle!,
            clock: context.environment.runtimeClock,
            invalidationSink: context.environment.renderInvalidationSink
        )

        let now = context.environment.runtimeClock.now()
        let palette = context.environment.palette

        // Render each notification on the configured surface and stack them.
        var stackedBuffer = FrameBuffer()
        for entry in activeEntries {
            let elapsed = now - entry.postedAt
            let opacity = NotificationTiming.opacity(
                elapsed: elapsed,
                visibleDuration: entry.duration
            )
            let fgColor = Color.palette.foreground.resolve(with: palette).opacity(opacity)

            switch surface {
            case .bordered:
                stackedBuffer.appendVertically(
                    borderedEntry(
                        entry,
                        foreground: fgColor,
                        border: palette.border.opacity(opacity),
                        context: context
                    )
                )
            case let .rail(accent, background):
                stackedBuffer.appendVertically(
                    railEntry(
                        entry,
                        foreground: fgColor,
                        accent: accent.resolve(with: palette).opacity(opacity),
                        background: background.resolve(with: palette),
                        context: context
                    )
                )
            }
        }

        guard !baseBuffer.isEmpty, !stackedBuffer.isEmpty else {
            return baseBuffer
        }

        // Expand the base buffer to fullscreen so the notification stack
        // is positioned relative to the terminal, not the content size.
        let screenWidth = context.availableWidth
        let screenHeight = context.availableHeight
        var fullscreenLines: [String] = []
        for row in 0..<screenHeight {
            if row < baseBuffer.lines.count {
                fullscreenLines.append(
                    baseBuffer.lines[row].padToVisibleWidth(screenWidth)
                )
            } else {
                fullscreenLines.append(String(repeating: " ", count: screenWidth))
            }
        }
        let fullscreenBuffer = FrameBuffer(lines: fullscreenLines)

        let offset = notificationOffset(
            stackSize: (stackedBuffer.width, stackedBuffer.height),
            screenSize: (screenWidth, screenHeight)
        )

        return fullscreenBuffer.composited(with: stackedBuffer, at: offset)
    }
}

// MARK: - Private Helpers

private extension NotificationHostModifier {
    /// Calculates the screen offset for the notification stack (always top-right).
    ///
    /// - Parameters:
    ///   - stackSize: The width and height of the stacked notification buffer.
    ///   - screenSize: The available terminal width and height.
    /// - Returns: The (x, y) position to place the stack.
    func notificationOffset(
        stackSize: (width: Int, height: Int),
        screenSize: (width: Int, height: Int)
    ) -> (x: Int, y: Int) {
        let xPosition = max(0, screenSize.width - stackSize.width - 1)
        return (xPosition, 1)
    }

    /// Starts a background task that triggers re-renders for fade animations
    /// and cleans up expired notifications.
    ///
    /// Uses a single shared token so only one animation task runs at a time.
    /// The task stops automatically when no notifications are active.
    func startAnimationTask(
        entries: [NotificationEntry],
        lifecycle: LifecycleManager,
        clock: RuntimeClock,
        invalidationSink: (any RenderInvalidationSink)?
    ) {
        let token = "notification-host-animation"

        guard !lifecycle.hasAppeared(token: token) else { return }
        _ = lifecycle.recordAppear(token: token) {}

        // Calculate the latest expiration time across all entries.
        let totalOverhead = NotificationTiming.fadeInDuration + NotificationTiming.fadeOutDuration
        let latestExpiry = entries.map { $0.postedAt + $0.duration + totalOverhead }
            .max() ?? 0

        lifecycle.startTask(token: token, priority: .medium) { [lifecycle, invalidationSink] in
            let triggerNanos: UInt64 = 23_800_000  // ~42 animation frames per second

            while !Task.isCancelled {
                let now = clock.now()
                if now > latestExpiry {
                    break
                }
                try? await Task.sleep(nanoseconds: triggerNanos)
                guard !Task.isCancelled else { break }
                invalidationSink?.invalidate(.renderOnly)
            }

            // Final render to clear expired notifications.
            lifecycle.resetAppearance(token: token)
            invalidationSink?.invalidate(.renderOnly)
        }
    }
}
