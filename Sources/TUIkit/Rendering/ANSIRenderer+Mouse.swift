//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ANSIRenderer+Mouse.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Mouse Capture

extension ANSIRenderer {
    /// Reports button presses with SGR coordinates.
    ///
    /// Mode `1000` reports press and release events; mode `1006` selects
    /// the SGR encoding, which is not limited to 223 columns. Hover
    /// reporting (`1002`, `1003`) stays off.
    static let enableMouseCapture = "\(csi)?1000h\(csi)?1006h"

    /// Stops button reporting and returns the mouse to the terminal.
    ///
    /// While capture is off, the terminal handles drag gestures itself, so
    /// the user can select and copy text with the mouse.
    static let disableMouseCapture = "\(csi)?1000l\(csi)?1006l"
}
