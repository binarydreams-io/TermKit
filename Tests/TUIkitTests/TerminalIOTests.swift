//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TerminalIOTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

@testable import TUIkit

// MARK: - Terminal I/O Tests

@Suite("Terminal I/O Tests")
@MainActor
struct TerminalIOTests {
  @Test("Reading retries after an interrupted system call")
  func readRetriesAfterInterruption() {
    let script = TerminalIOScript(
      reads: [.failure(EINTR), .bytes([0x41])]
    )
    let terminal = Terminal(systemCalls: script.systemCalls)

    #expect(terminal.readBytes() == [0x41])
    #expect(script.readCallCount == 2)
  }

  @Test("Writing retries interruptions and partial writes")
  func writeRetriesInterruptionsAndPartialWrites() {
    let script = TerminalIOScript(
      writes: [.failure(EINTR), .count(2), .count(3)]
    )
    let terminal = Terminal(systemCalls: script.systemCalls)

    terminal.write("Hello")

    #expect(script.writtenBytes == Array("Hello".utf8))
    #expect(script.writeCallCount == 3)
  }

  @Test("A read failure is reported once")
  func readFailureIsReportedOnce() {
    let script = TerminalIOScript(reads: [.failure(EIO)])
    let terminal = Terminal(systemCalls: script.systemCalls)

    #expect(terminal.readBytes().isEmpty)
    #expect(
      terminal.takeIOFailure() == TerminalIOFailure(
        operation: .read,
        errorCode: EIO,
        remainingByteCount: 1
      )
    )
    #expect(terminal.takeIOFailure() == nil)
  }

  @Test("A write failure reports its remaining byte count")
  func writeFailureReportsRemainingBytes() {
    let script = TerminalIOScript(
      writes: [.count(2), .failure(EIO)]
    )
    let terminal = Terminal(systemCalls: script.systemCalls)

    terminal.write("Hello")

    #expect(script.writtenBytes == Array("He".utf8))
    #expect(
      terminal.takeIOFailure() == TerminalIOFailure(
        operation: .write,
        errorCode: EIO,
        remainingByteCount: 3
      )
    )
    #expect(terminal.takeIOFailure() == nil)
  }

  @Test("Runtime input preserves multiple events from one read")
  func runtimeInputPreservesMultipleEvents() {
    let script = TerminalIOScript(reads: [.bytes(Array("ab".utf8))])
    let terminal = Terminal(systemCalls: script.systemCalls)

    #expect(terminal.readInputEvent() == .key(KeyEvent(character: "a")))
    #expect(terminal.readInputEvent() == .key(KeyEvent(character: "b")))
    #expect(script.readCallCount == 1)
  }

  @Test("Fragmented escape sequences are not emitted as standalone Escape")
  func fragmentedEscapeSequencesRemainComplete() {
    let cases: [(fragments: [[UInt8]], expected: InputEvent)] = [
      ([[0x1B], Array("[A".utf8)], .key(KeyEvent(key: .up))),
      ([[0x1B], Array("O".utf8), Array("P".utf8)], .key(KeyEvent(key: .f1))),
      (
        [[0x1B], Array("[<0;2".utf8), Array(";3M".utf8)],
        .mouse(MouseEvent(action: .press(.left), column: 1, row: 2))
      ),
      (
        [[0x1B], Array("[200~hello".utf8), [0x1B], Array("[201~".utf8)],
        .key(KeyEvent(key: .paste("hello")))
      )
    ]

    for parseCase in cases {
      let reads = parseCase.fragments.flatMap { fragment in
        [TerminalIOScript.ReadStep.bytes(fragment), .bytes([])]
      }
      let terminal = Terminal(systemCalls: TerminalIOScript(reads: reads).systemCalls)

      for index in parseCase.fragments.indices {
        let event = terminal.readInputEvent()
        if index == parseCase.fragments.count - 1 {
          #expect(event == parseCase.expected)
        } else {
          #expect(event == nil)
        }
      }
    }
  }

  @Test("Standalone Escape is emitted after a short delay", .timeLimit(.minutes(1)))
  func standaloneEscapeUsesBoundedDelay() async throws {
    let script = TerminalIOScript(reads: [.bytes([0x1B]), .bytes([])])
    let terminal = Terminal(systemCalls: script.systemCalls)

    #expect(terminal.readInputEvent() == nil)

    try await ContinuousClock().sleep(for: .milliseconds(30))
    #expect(terminal.readInputEvent() == .key(KeyEvent(key: .escape)))
  }

  @Test("Legacy key input skips mouse events without losing the next key")
  func legacyKeyInputRemainsCompatible() {
    let script = TerminalIOScript(
      reads: [.bytes(Array("\u{1B}[<0;2;3Ma".utf8))]
    )
    let terminal = Terminal(systemCalls: script.systemCalls)

    #expect(terminal.readKeyEvent() == KeyEvent(character: "a"))
  }

  @Test("Raw mode enables SGR button input and cleanup disables mouse modes")
  func rawModeConfiguresMouseInput() {
    let script = TerminalIOScript(
      writes: Array(repeating: .count(Int.max), count: 4)
    )
    let terminal = Terminal(inputFileDescriptor: -1, systemCalls: script.systemCalls)

    terminal.enableRawMode()
    terminal.disableRawMode()

    let output = String(decoding: script.writtenBytes, as: UTF8.self)
    #expect(output.contains("\u{1B}[?1000h"))
    #expect(output.contains("\u{1B}[?1006h"))
    #expect(output.contains("\u{1B}[?1003h") == false)
    #expect(output.contains("\u{1B}[?1000l"))
    #expect(output.contains("\u{1B}[?1002l"))
    #expect(output.contains("\u{1B}[?1003l"))
    #expect(output.contains("\u{1B}[?1006l"))
  }

  @Test("Mouse capture stays quiet until raw mode is enabled")
  func mouseCaptureIsNoOpBeforeRawMode() {
    let script = TerminalIOScript(
      writes: Array(repeating: .count(Int.max), count: 4)
    )
    let terminal = Terminal(inputFileDescriptor: -1, systemCalls: script.systemCalls)

    terminal.setMouseCaptureEnabled(true)

    #expect(script.writtenBytes.isEmpty)
  }

  @Test("Cleanup resets every mouse mode after selection mode released capture")
  func cleanupResetsMouseModesAfterCaptureRelease() {
    let script = TerminalIOScript(
      writes: Array(repeating: .count(Int.max), count: 6)
    )
    let terminal = Terminal(inputFileDescriptor: -1, systemCalls: script.systemCalls)

    terminal.enableRawMode()
    terminal.setMouseCaptureEnabled(false)
    terminal.disableRawMode()

    // Releasing capture turns off 1000 and 1006 only. Cleanup must still
    // reset the modes an external program could have left on.
    let output = String(decoding: script.writtenBytes, as: UTF8.self)
    #expect(output.contains("\u{1B}[?1003l"))
    #expect(output.contains("\u{1B}[?1016l"))
  }

  @Test("Terminal deinit disables mouse modes")
  func deinitDisablesMouseInput() {
    let script = TerminalIOScript(
      writes: Array(repeating: .count(Int.max), count: 4)
    )
    var terminal: Terminal? = Terminal(inputFileDescriptor: -1, systemCalls: script.systemCalls)

    terminal?.enableRawMode()
    terminal = nil

    let output = String(decoding: script.writtenBytes, as: UTF8.self)
    #expect(output.contains("\u{1B}[?1000l"))
    #expect(output.contains("\u{1B}[?1006l"))
  }
}

// MARK: - Test Support

private final class TerminalIOScript: @unchecked Sendable {
  enum ReadStep: Sendable {
    case failure(Int32)
    case bytes([UInt8])
  }

  enum WriteStep: Sendable {
    case failure(Int32)
    case count(Int)
  }

  private let lock = NSLock()
  private var reads: [ReadStep]
  private var writes: [WriteStep]
  private var currentErrorCode: Int32 = 0
  private var storedReadCallCount = 0
  private var storedWriteCallCount = 0
  private var storedWrittenBytes: [UInt8] = []

  init(
    reads: [ReadStep] = [],
    writes: [WriteStep] = []
  ) {
    self.reads = reads
    self.writes = writes
  }

  var systemCalls: TerminalSystemCalls {
    TerminalSystemCalls(
      read: { [self] fileDescriptor, buffer, count in
        read(fileDescriptor: fileDescriptor, into: buffer, count: count)
      },
      write: { [self] fileDescriptor, buffer, count in
        write(fileDescriptor: fileDescriptor, from: buffer, count: count)
      },
      errorCode: { [self] in errorCode }
    )
  }

  var readCallCount: Int {
    withLock { storedReadCallCount }
  }

  var writeCallCount: Int {
    withLock { storedWriteCallCount }
  }

  var writtenBytes: [UInt8] {
    withLock { storedWrittenBytes }
  }
}

extension TerminalIOScript {
  fileprivate var errorCode: Int32 {
    withLock { currentErrorCode }
  }

  fileprivate func read(
    fileDescriptor _: Int32,
    into buffer: UnsafeMutableRawPointer?,
    count: Int
  ) -> Int {
    withLock {
      storedReadCallCount += 1
      guard !reads.isEmpty else { return 0 }

      switch reads.removeFirst() {
      case let .failure(errorCode):
        currentErrorCode = errorCode
        return -1
      case let .bytes(bytes):
        currentErrorCode = 0
        guard let buffer else { return 0 }
        let byteCount = min(count, bytes.count)
        for index in 0 ..< byteCount {
          buffer.storeBytes(of: bytes[index], toByteOffset: index, as: UInt8.self)
        }
        return byteCount
      }
    }
  }

  fileprivate func write(
    fileDescriptor _: Int32,
    from buffer: UnsafeRawPointer?,
    count: Int
  ) -> Int {
    withLock {
      storedWriteCallCount += 1
      guard !writes.isEmpty else { return 0 }

      switch writes.removeFirst() {
      case let .failure(errorCode):
        currentErrorCode = errorCode
        return -1
      case let .count(requestedCount):
        currentErrorCode = 0
        guard let buffer else { return 0 }
        let byteCount = min(count, requestedCount)
        let bytes = buffer.assumingMemoryBound(to: UInt8.self)
        storedWrittenBytes.append(contentsOf: UnsafeBufferPointer(start: bytes, count: byteCount))
        return byteCount
      }
    }
  }

  private func withLock<Result>(_ body: () -> Result) -> Result {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
