//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Terminal.swift
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

// MARK: - Terminal System Calls

/// Injectable POSIX calls used by terminal input and output.
struct TerminalSystemCalls: Sendable {
  /// Reads bytes from a file descriptor.
  let read: @Sendable (Int32, UnsafeMutableRawPointer?, Int) -> Int

  /// Writes bytes to a file descriptor.
  let write: @Sendable (Int32, UnsafeRawPointer?, Int) -> Int

  /// Returns the current thread-local POSIX error code.
  let errorCode: @Sendable () -> Int32

  /// Production calls supplied by the active platform module.
  static let system = Self(
    read: platformRead,
    write: platformWrite,
    errorCode: { errno }
  )
}

/// Calls the active platform's POSIX `read` function.
private func platformRead(
  _ fileDescriptor: Int32,
  _ buffer: UnsafeMutableRawPointer?,
  _ count: Int
) -> Int {
  #if canImport(Glibc)
  Glibc.read(fileDescriptor, buffer, count)
  #elseif canImport(Musl)
  Musl.read(fileDescriptor, buffer, count)
  #else
  Darwin.read(fileDescriptor, buffer, count)
  #endif
}

/// Calls the active platform's POSIX `write` function.
private func platformWrite(
  _ fileDescriptor: Int32,
  _ buffer: UnsafeRawPointer?,
  _ count: Int
) -> Int {
  #if canImport(Glibc)
  Glibc.write(fileDescriptor, buffer, count)
  #elseif canImport(Musl)
  Musl.write(fileDescriptor, buffer, count)
  #else
  Darwin.write(fileDescriptor, buffer, count)
  #endif
}

// Platform-specific type for `termios` flag fields.
//
// Darwin uses `UInt` (64-bit), Linux uses `tcflag_t` (`UInt32`).
// This typealias ensures flag bitmask operations compile on both.
#if os(Linux)
typealias TermFlag = UInt32
#else
typealias TermFlag = UInt
#endif

/// Represents the terminal and controls input and output.
///
/// `Terminal` is the central interface to the terminal. It provides:
/// - Terminal size queries
/// - Raw mode configuration
/// - Safe input and output
/// - Frame-buffered output (all writes collected, normally flushed in one syscall)
///
/// ## Output Buffering
///
/// During rendering, call ``beginFrame()`` before writing and ``endFrame()``
/// after. All ``write(_:)`` calls between them are collected in an internal
/// `[UInt8]` buffer and normally flushed as a single `write()` syscall, reducing
/// per-frame syscalls from ~40+ to one in the normal case. Interrupted and
/// partial writes are retried until the frame is complete or an error is surfaced.
///
/// Outside of a frame (setup, teardown), ``write(_:)`` writes immediately
/// as before — safe by default.
///
/// ## Thread Safety
///
/// `Terminal` is `@MainActor` isolated. All terminal operations must occur
/// on the main thread, which is enforced by the Swift concurrency system.
@MainActor
final class Terminal: TerminalProtocol, TerminalFailureReporting, TerminalInputScheduling {
  /// Maximum delay before a standalone Escape key is emitted.
  static let standaloneEscapeTimeout: Duration = .milliseconds(20)

  /// File descriptor used for terminal input.
  let inputFileDescriptor: Int32

  /// File descriptor used for terminal output.
  let outputFileDescriptor: Int32

  /// POSIX calls used for input and output.
  let systemCalls: TerminalSystemCalls

  /// The first terminal I/O failure not yet consumed by the runtime.
  var pendingIOFailure: TerminalIOFailure?

  /// Buffers input bytes until complete keyboard or mouse events are available.
  var inputParser = TerminalInputParser()

  /// Monotonic clock used to distinguish Escape from an escape-sequence prefix.
  let inputClock = ContinuousClock()

  /// Deadline for the currently buffered standalone Escape byte.
  var standaloneEscapeDeadline: ContinuousClock.Instant?

  /// Whether raw mode is active.
  var isRawMode = false

  /// Whether terminal mouse reporting is active.
  var isMouseInputEnabled = false

  /// The original terminal settings.
  var originalTermios: termios?

  /// Whether frame buffering is active.
  ///
  /// When `true`, ``write(_:)`` appends to ``frameBuffer`` instead of
  /// writing to `STDOUT_FILENO` immediately.
  var isBuffering = false

  /// Collects all output bytes during a buffered frame.
  ///
  /// Starts empty, grows via ``write(_:)`` calls, flushed by ``endFrame()``.
  /// Initial capacity of 16 KB covers typical frames without reallocation.
  var frameBuffer: [UInt8] = []

  /// Creates a new terminal instance.
  init(
    inputFileDescriptor: Int32 = STDIN_FILENO,
    outputFileDescriptor: Int32 = STDOUT_FILENO,
    systemCalls: TerminalSystemCalls = .system
  ) {
    self.inputFileDescriptor = inputFileDescriptor
    self.outputFileDescriptor = outputFileDescriptor
    self.systemCalls = systemCalls
    frameBuffer.reserveCapacity(16384)
  }

  /// Destructor ensures raw mode and mouse reporting are disabled.
  ///
  /// Note: `deinit` cannot be actor-isolated, so we use `MainActor.assumeIsolated`
  /// which is safe because Terminal instances are only created and destroyed
  /// on the main thread (in AppRunner).
  deinit {
    MainActor.assumeIsolated {
      disableRawMode()
    }
  }
}

// MARK: - I/O Failure Reporting

extension Terminal {
  /// Records the first terminal I/O failure until the runtime consumes it.
  func recordIOFailure(
    operation: TerminalIOFailure.Operation,
    errorCode: Int32,
    remainingByteCount: Int
  ) {
    guard pendingIOFailure == nil else { return }
    pendingIOFailure = TerminalIOFailure(
      operation: operation,
      errorCode: errorCode,
      remainingByteCount: remainingByteCount
    )
  }
}
