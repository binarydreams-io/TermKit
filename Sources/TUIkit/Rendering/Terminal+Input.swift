//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Terminal+Input.swift
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

// MARK: - Terminal Input

extension Terminal {
  /// Reads raw bytes from the terminal, handling escape sequences.
  ///
  /// Reads exactly one key event worth of bytes. For escape sequences,
  /// reads byte-by-byte until a CSI terminator is found, preventing
  /// multiple sequences from being read at once during fast key repeat.
  ///
  /// - Parameter maxBytes: Maximum bytes to read (default: 8).
  /// - Returns: The bytes read, or empty array on timeout/error.
  func readBytes(maxBytes: Int = 8) -> [UInt8] {
    guard let firstByte = readByte() else { return [] }

    // Not an escape sequence - return single byte
    guard firstByte == 0x1B else {
      return [firstByte]
    }

    // Read the next byte to determine sequence type
    var result: [UInt8] = [0x1B]
    guard let nextByte = readByte() else {
      // Just ESC alone
      return result
    }

    result.append(nextByte)

    // CSI sequence: ESC [
    if nextByte == 0x5B { // '['
      // Read until we find a CSI terminator (letter A-Za-z or ~)
      for _ in 0 ..< (maxBytes - 2) {
        guard let parameterByte = readByte() else { break }

        result.append(parameterByte)

        // CSI terminators: letters (0x40-0x7E) mark end of sequence
        // Common: A-D (arrows), H/F (home/end), Z (shift-tab), ~ (extended)
        if parameterByte >= 0x40, parameterByte <= 0x7E {
          break
        }
      }
    } else if nextByte == 0x4F { // SS3 sequence: ESC O
      // Read one more byte for F1-F4 keys
      if let functionByte = readByte() {
        result.append(functionByte)
      }
    }
    // Alt+key: ESC followed by single key - already have both bytes

    return result
  }

  /// Reads a key event from the terminal.
  ///
  /// When bracketed paste mode is active the terminal wraps pasted text
  /// in `ESC[200~` ... `ESC[201~` markers. This method detects the start
  /// marker, buffers all bytes until the end marker, and returns the
  /// entire pasted text as a single `Key.paste(String)` event.
  ///
  /// - Returns: The key event, or nil on timeout/error.
  func readKeyEvent() -> KeyEvent? {
    while let event = readInputEvent() {
      if case let .key(keyEvent) = event {
        return keyEvent
      }
    }
    return nil
  }

  /// Reads a complete keyboard or mouse event from buffered terminal bytes.
  ///
  /// - Returns: The input event, or `nil` if no complete event is available.
  func readInputEvent() -> InputEvent? {
    while true {
      if let event = inputParser.nextEvent() {
        standaloneEscapeDeadline = nil
        return event
      }

      if inputParser.hasStandaloneEscape {
        let now = inputClock.now
        if let standaloneEscapeDeadline {
          if now >= standaloneEscapeDeadline {
            self.standaloneEscapeDeadline = nil
            return inputParser.takeStandaloneEscape()
          }
        } else {
          standaloneEscapeDeadline = now.advanced(by: Self.standaloneEscapeTimeout)
        }
      } else {
        standaloneEscapeDeadline = nil
      }

      let bytes = readInputBytes()
      guard bytes.isEmpty == false else { return nil }
      inputParser.append(bytes)
    }
  }

  var hasBufferedInput: Bool {
    inputParser.hasBufferedInput
  }

  var pendingInputRetryDelay: Duration? {
    guard inputParser.hasStandaloneEscape, let standaloneEscapeDeadline else { return nil }
    return max(.zero, inputClock.now.duration(to: standaloneEscapeDeadline))
  }
}

// MARK: - Private Helpers

extension Terminal {
  /// Reads one available block of input bytes.
  private func readInputBytes(maxBytes: Int = 256) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: maxBytes)

    while true {
      let result = bytes.withUnsafeMutableBytes { buffer in
        systemCalls.read(inputFileDescriptor, buffer.baseAddress, maxBytes)
      }
      if result > 0 {
        return Array(bytes.prefix(result))
      }
      if result < 0, systemCalls.errorCode() == EINTR {
        continue
      }
      if result < 0 {
        recordIOFailure(
          operation: .read,
          errorCode: systemCalls.errorCode(),
          remainingByteCount: maxBytes
        )
      }
      return []
    }
  }

  /// Reads one byte, retrying when the system call is interrupted.
  private func readByte() -> UInt8? {
    var byte: UInt8 = 0

    while true {
      let result = withUnsafeMutableBytes(of: &byte) { buffer in
        systemCalls.read(inputFileDescriptor, buffer.baseAddress, 1)
      }

      if result > 0 {
        return byte
      }
      if result < 0, systemCalls.errorCode() == EINTR {
        continue
      }
      if result < 0 {
        recordIOFailure(
          operation: .read,
          errorCode: systemCalls.errorCode(),
          remainingByteCount: 1
        )
      }
      return nil
    }
  }
}
