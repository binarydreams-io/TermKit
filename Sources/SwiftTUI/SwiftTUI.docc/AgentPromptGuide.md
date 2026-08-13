# Agent Prompt

``AgentPrompt`` accepts a ``Binding`` to ``PromptDocument``. The prompt updates the binding for text, bracketed paste, newlines, and autocomplete insertions.

```swift
import SwiftTUI

struct PromptView: View {
    @State private var document = PromptDocument()

    var graphBody: [NodeDescriptor] {
        AgentPrompt<String>(
            $document,
            actions: AgentPromptActions(
                submit: { document in send(document.text) },
                cancel: {},
                paste: { _ in },
                attach: { _ in }
            ),
            leadingAccessory: { Text(">") },
            trailingAccessory: { Text("Enter to send") }
        ).graphBody
    }

    private func send(_ text: String) {}
}
```

The runtime retains the leading and trailing accessory views. Their identity and state remain stable when prompt content changes. Enter submits the prompt. Modified Enter inserts a newline. Escape calls the cancel action.

The component owns presentation and temporary edit state. Networking, persistence, provider selection, and tool execution remain application responsibilities.
