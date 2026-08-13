swift build --target SwiftTUI -Xswiftc -warnings-as-errors
swift-symbolgraph-extract -module-name SwiftTUI
docc convert Sources/SwiftTUI/SwiftTUI.docc --warnings-as-errors
redirect=/documentation/swifttui/
