# Credits

## TUIkit

SwiftTUI began as a fork of [TUIkit](https://github.com/phranck/TUIkit). TUIkit supplied the initial Swift terminal application code, terminal conventions, control vocabulary, and behavior tests.

SwiftTUI replaces the original rendering and runtime architecture with packed cells, a retained graph, damage tracking, and a shared scheduler. The legacy targets remain internal regression evidence.

## OpenCode

[OpenCode](https://github.com/anomalyco/opencode) informed the product requirements for coding-agent interfaces. SwiftTUI adapts interaction concepts such as prompts, tool activity, permissions, questions, diagnostics, and session chrome.

The Swift implementation uses generic presentation models and independent names. It does not include OpenCode branding or application logic.

## Swift Ecosystem

SwiftTUI uses Swift Testing and the Swift package manager. Pure Swift image codecs and their licenses are listed in `Vendor/README.md`.
