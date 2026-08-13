//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Terminal+Output.swift
//
//  Created by LAYERED.work
//  License: MIT

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Terminal Output

extension Terminal {
  /// Begins a buffered frame.
  ///
  /// After this call, all ``write(_:)`` calls append to an internal
  /// `[UInt8]` buffer instead of issuing syscalls. Call ``endFrame()``
  /// to flush the collected output, normally in a single `write()` syscall.
  func beginFrame() {
    guard !isBuffering else { return }
    isBuffering = true
    frameBuffer.removeAll(keepingCapacity: true)
  }

  /// Ends a buffered frame and flushes all collected output.
  func endFrame() {
    guard isBuffering else { return }
    isBuffering = false
    flushBuffer()
  }

  /// Writes a string to the terminal.
  ///
  /// When frame buffering is active (between ``beginFrame()`` and
  /// ``endFrame()``), the string's UTF-8 bytes are appended to the
  /// internal buffer. Otherwise, the bytes are written directly to
  /// `STDOUT_FILENO` via the POSIX `write` syscall.
  ///
  /// - Parameter string: The string to write.
  func write(_ string: String) {
    if isBuffering {
      appendToBuffer(string)
    } else {
      writeImmediate(string)
    }
  }

  /// Moves the cursor to the specified position.
  ///
  /// - Parameters:
  ///   - row: The row (1-based).
  ///   - column: The column (1-based).
  func moveCursor(toRow row: Int, column: Int) {
    write(ANSIRenderer.moveCursor(toRow: row, column: column))
  }

  /// Hides the cursor.
  func hideCursor() {
    write(ANSIRenderer.hideCursor)
  }

  /// Shows the cursor.
  func showCursor() {
    write(ANSIRenderer.showCursor)
  }

  /// Switches to the alternate screen buffer.
  func enterAlternateScreen() {
    write(ANSIRenderer.enterAlternateScreen)
  }

  /// Exits the alternate screen buffer.
  func exitAlternateScreen() {
    write(ANSIRenderer.exitAlternateScreen)
  }

  /// Sets the terminal window and icon title.
  ///
  /// The sequence bypasses the frame buffer: a title change is terminal
  /// state, not screen content, and must not wait for the next flush.
  ///
  /// - Parameter title: The title text.
  func setWindowTitle(_ title: String) {
    writeImmediate(ANSIRenderer.setWindowTitle(title))
  }

  /// Removes and returns the first pending terminal I/O failure.
  func takeIOFailure() -> TerminalIOFailure? {
    defer { pendingIOFailure = nil }
    return pendingIOFailure
  }
}

// MARK: - Private Helpers

extension Terminal {
  /// Appends a string's UTF-8 bytes to the frame buffer.
  private func appendToBuffer(_ string: String) {
    frameBuffer.append(contentsOf: string.utf8)
  }

  /// Writes all buffered bytes, retrying interrupted or partial syscalls.
  private func flushBuffer() {
    guard !frameBuffer.isEmpty else { return }
    frameBuffer.withUnsafeBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else { return }
      writeBytes(baseAddress, count: buffer.count)
    }
    frameBuffer.removeAll(keepingCapacity: true)
  }

  /// Writes a string directly to `STDOUT_FILENO` without buffering.
  func writeImmediate(_ string: String) {
    // Safe: UTF8 string is valid UInt8 sequence; rebinding preserves memory layout.
    string.utf8CString.withUnsafeBufferPointer { buffer in
      let count = buffer.count - 1
      guard count >= 1, let baseAddress = buffer.baseAddress else { return }
      baseAddress.withMemoryRebound(to: UInt8.self, capacity: count) { pointer in
        writeBytes(pointer, count: count)
      }
    }
  }

  /// Writes every byte, retrying interrupted and partial system calls.
  private func writeBytes(_ baseAddress: UnsafePointer<UInt8>, count: Int) {
    var written = 0

    while written < count {
      let result = systemCalls.write(outputFileDescriptor, baseAddress + written, count - written)
      if result > 0 {
        written += result
      } else if result < 0, systemCalls.errorCode() == EINTR {
        continue
      } else {
        recordIOFailure(
          operation: .write,
          errorCode: result < 0 ? systemCalls.errorCode() : EIO,
          remainingByteCount: count - written
        )
        return
      }
    }
  }
}
