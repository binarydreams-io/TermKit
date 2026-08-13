//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ANSIRenderer+WindowTitle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Window Title

extension ANSIRenderer {
    /// Saves the current window title on the terminal's title stack.
    ///
    /// XTerm window operation `22;0` pushes both the icon name and the
    /// window title. Write it once at startup so ``popWindowTitle``
    /// restores the shell's own title on exit.
    static let pushWindowTitle = "\(csi)22;0t"

    /// Restores the window title saved by ``pushWindowTitle``.
    ///
    /// XTerm window operation `23;0` pops both the icon name and the
    /// window title. Terminals without a title stack ignore it.
    static let popWindowTitle = "\(csi)23;0t"

    /// Generates the OSC 0 sequence that sets the window and icon title.
    ///
    /// - Parameter title: The title text.
    /// - Returns: The escape sequence, terminated by BEL.
    static func setWindowTitle(_ title: String) -> String {
        "\(escape)]0;\(title)\u{07}"
    }
}
