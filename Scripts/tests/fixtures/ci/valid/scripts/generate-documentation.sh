swift build --target SwiftTUI -Xswiftc -warnings-as-errors
swift-symbolgraph-extract \
    -module-name SwiftTUI \
    -experimental-allowed-reexported-modules=TUIFoundation,TUITerminal,TUIRenderer,TUIViewGraph,TUILayout,TUIAnimation,TUIControls,TUIDesign,TUIRichText,TUIAgentUI,TUIRuntime
docc convert Sources/SwiftTUI/SwiftTUI.docc --warnings-as-errors
redirect=/documentation/swifttui/
