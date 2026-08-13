//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Terminal+Modes.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Terminal Modes

extension Terminal {
  /// Returns the current terminal size.
  ///
  /// - Returns: A tuple with width and height in characters/lines.
  func getSize() -> (width: Int, height: Int) {
    var windowSize = winsize()

    #if canImport(Glibc) || canImport(Musl)
    let result = ioctl(outputFileDescriptor, UInt(TIOCGWINSZ), &windowSize)
    #else
    let result = ioctl(outputFileDescriptor, TIOCGWINSZ, &windowSize)
    #endif

    if result == 0, windowSize.ws_col > 0, windowSize.ws_row > 0 {
      return (Int(windowSize.ws_col), Int(windowSize.ws_row))
    }

    // Fallback to environment variables
    let cols = ProcessInfo.processInfo.environment["COLUMNS"].flatMap(Int.init) ?? 80
    let rows = ProcessInfo.processInfo.environment["LINES"].flatMap(Int.init) ?? 24

    return (cols, rows)
  }

  /// Enables raw mode for direct character handling.
  ///
  /// In raw mode:
  /// - Each keystroke is reported immediately (without Enter)
  /// - Echo is disabled
  /// - Signals like Ctrl+C are not automatically processed
  func enableRawMode() {
    guard !isRawMode else { return }

    var raw = termios()
    tcgetattr(inputFileDescriptor, &raw)
    originalTermios = raw

    raw.c_lflag &= ~TermFlag(ECHO | ICANON | ISIG | IEXTEN)
    raw.c_iflag &= ~TermFlag(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
    raw.c_oflag &= ~TermFlag(OPOST)
    raw.c_cflag |= TermFlag(CS8)

    // Safe: termios.c_cc is a fixed-size array; rebinding to cc_t is valid.
    withUnsafeMutablePointer(to: &raw.c_cc) { pointer in
      pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { buffer in
        buffer[Int(VMIN)] = 0
        buffer[Int(VTIME)] = 0
      }
    }

    tcsetattr(inputFileDescriptor, TCSAFLUSH, &raw)
    isRawMode = true

    // Enable bracketed paste mode so that terminal paste operations
    // are wrapped in ESC[200~ ... ESC[201~ markers. This allows the
    // application to detect pasted text and insert it as a single
    // bulk operation instead of processing each character individually.
    writeImmediate("\u{1B}[?2004h")

    // Enable button events with SGR coordinates. Hover reporting remains disabled.
    writeImmediate(ANSIRenderer.enableMouseCapture)
    isMouseInputEnabled = true
  }

  /// Enables or disables mouse reporting for the running session.
  ///
  /// Selection mode releases the mouse so the terminal can select text.
  /// Mouse reporting only exists inside a raw session, so this does
  /// nothing before ``enableRawMode()`` and after ``disableRawMode()``.
  ///
  /// - Parameter enabled: Whether the application receives mouse events.
  func setMouseCaptureEnabled(_ enabled: Bool) {
    guard isRawMode else { return }

    writeImmediate(enabled ? ANSIRenderer.enableMouseCapture : ANSIRenderer.disableMouseCapture)
    isMouseInputEnabled = enabled
  }

  /// Disables raw mode and restores normal terminal operation.
  func disableRawMode() {
    // `isRawMode` covers a session that released capture for selection
    // mode: the modes this reset covers are wider than the two that
    // `setMouseCaptureEnabled(false)` turned off.
    if isRawMode || isMouseInputEnabled {
      // Reset every common mouse mode in case terminal state changed externally.
      writeImmediate(
        "\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1001l\u{1B}[?1002l\u{1B}[?1003l"
          + "\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l"
      )
      isMouseInputEnabled = false
    }

    guard isRawMode, var original = originalTermios else { return }

    // Disable bracketed paste mode before restoring terminal state.
    writeImmediate("\u{1B}[?2004l")

    tcsetattr(inputFileDescriptor, TCSAFLUSH, &original)
    isRawMode = false
  }
}
