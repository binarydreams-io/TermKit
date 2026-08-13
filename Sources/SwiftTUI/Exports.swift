import Foundation

@_exported import TUIAgentUI
@_exported import TUIAnimation
@_exported import TUIControls
@_exported import TUIDesign
@_exported import TUIFoundation
@_exported import TUILayout
@_exported import TUIRenderer
@_exported import TUIRichText
@_exported import TUIRuntime
@_exported import TUITerminal
@_exported import TUIViewGraph

public enum SwiftTUIRelease {
    public static let version: String = {
        guard let url = Bundle.module.url(forResource: "VERSION", withExtension: nil) else {
            preconditionFailure("SwiftTUI VERSION resource is missing.")
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            preconditionFailure("SwiftTUI VERSION resource could not be read: \(error)")
        }
    }()
}
