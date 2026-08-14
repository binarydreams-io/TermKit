# Agent Prompt

Build a prompt editor that reports user actions to an agent application.

Use ``AgentPrompt`` to edit a ``PromptDocument`` and report prompt actions to your application.

A bound prompt updates its ``Binding`` after text edits, paste events, newline insertion, and completion insertion.

```swift
import TermKit

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

The runtime retains both accessory views when the document changes. Their identity and state remain stable.

Enter submits the document. Modified Enter inserts a newline. Escape calls the cancel action.

The prompt owns its presentation and temporary edit state. Your application owns persistence, network requests, provider selection, and tool execution.
