import Dispatch
@testable import TermKit
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Darwin) || canImport(Glibc)
private let terminalTestActivationBytes = Array(
  "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[?1002h\u{1B}[?1006h\u{1B}[?1004h".utf8
)
private let terminalTestDeactivationBytes = Array(
  ("\u{1B}[?1004l"
    + "\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1001l\u{1B}[?1002l\u{1B}[?1003l"
    + "\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l"
    + "\u{1B}[?2004l\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l").utf8
)

private func makeTerminalTestTransport(pty: PTYPair) -> TerminalTransport {
  TerminalTransport(
    inputFileDescriptor: pty.slaveFileDescriptor,
    outputFileDescriptor: pty.slaveFileDescriptor
  )
}

private func terminalTestSignalHandlerAddress(_ action: sigaction) -> UInt {
  #if canImport(Darwin)
  unsafeBitCast(action.__sigaction_u.__sa_handler, to: UInt.self)
  #else
  unsafeBitCast(action.__sigaction_handler.sa_handler, to: UInt.self)
  #endif
}
#endif

@Suite("Terminal event source", .serialized)
struct TerminalEventSourceTests {
  #if canImport(Darwin) || canImport(Glibc)
  @Test
  func `PTY input wakes the event source`() throws {
    let pty = try PTYPair()
    let transport = TerminalTransport(
      inputFileDescriptor: pty.slaveFileDescriptor,
      outputFileDescriptor: pty.slaveFileDescriptor
    )
    let session = TerminalSession(transport: transport)
    let activationByteCount = "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[?1002h\u{1B}[?1006h\u{1B}[?1004h".utf8.count
    let start = try pty.captureOutput(exactByteCount: activationByteCount) {
      try session.start()
    }
    _ = try start.result.get()
    let source = try TerminalEventSource(inputFileDescriptor: pty.slaveFileDescriptor)

    try pty.writeToMaster([0x41])

    #expect(try source.nextEvent(timeout: .milliseconds(500)) == .inputReady)
    #expect(try transport.read(maximumByteCount: 1) == [0x41])
    let deactivationByteCount =
      ("\u{1B}[?1004l"
        + "\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1001l\u{1B}[?1002l\u{1B}[?1003l"
        + "\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l"
        + "\u{1B}[?2004l\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l").utf8.count
    let stop = try pty.captureOutput(exactByteCount: deactivationByteCount) {
      try session.stop()
    }
    _ = try stop.result.get()
  }

  @Test
  func `PTY input delivers bracketed paste and SGR mouse events`() throws {
    let pty = try PTYPair()
    let originalAttributes = try pty.attributesSnapshot()
    let transport = makeTerminalTestTransport(pty: pty)
    let session = TerminalSession(transport: transport)
    let start = try pty.captureOutput(exactByteCount: terminalTestActivationBytes.count) {
      try session.start()
    }
    #expect(try start.result.get() == .started)
    #expect(start.output == terminalTestActivationBytes)
    let source = try TerminalEventSource(inputFileDescriptor: pty.slaveFileDescriptor)
    var parser = TerminalInputParser()

    let pasteBytes = Array("\u{1B}[200~hello\nfrom pty\u{1B}[201~".utf8)
    try pty.writeToMaster(pasteBytes)
    #expect(try source.nextEvent(timeout: .milliseconds(500)) == .inputReady)
    let pasteInput = try transport.read(maximumByteCount: pasteBytes.count)
    #expect(pasteInput == pasteBytes)
    #expect(parser.append(pasteInput).events == [.paste("hello\nfrom pty")])

    let mouseBytes = Array("\u{1B}[<20;8;4M".utf8)
    try pty.writeToMaster(mouseBytes)
    #expect(try source.nextEvent(timeout: .milliseconds(500)) == .inputReady)
    let mouseInput = try transport.read(maximumByteCount: mouseBytes.count)
    #expect(mouseInput == mouseBytes)
    #expect(
      parser.append(mouseInput).events == [
        .mouse(
          TerminalMouseEvent(
            action: .press(.left),
            position: TerminalCellPoint(column: 7, row: 3),
            modifiers: [.shift, .control]
          )
        )
      ]
    )

    let stop = try pty.captureOutput(exactByteCount: terminalTestDeactivationBytes.count) {
      try session.stop()
    }
    #expect(try stop.result.get() == .stopped)
    #expect(stop.output == terminalTestDeactivationBytes)
    #expect(try pty.attributesSnapshot() == originalAttributes)
    withExtendedLifetime(source) {}
  }

  @Test
  func `PTY resize signal delivers the updated terminal size`() throws {
    let pty = try PTYPair()
    let originalAttributes = try pty.attributesSnapshot()
    let session = TerminalSession(transport: makeTerminalTestTransport(pty: pty))
    let start = try pty.captureOutput(exactByteCount: terminalTestActivationBytes.count) {
      try session.start()
    }
    #expect(try start.result.get() == .started)
    #expect(start.output == terminalTestActivationBytes)
    let source = try TerminalEventSource(inputFileDescriptor: pty.slaveFileDescriptor)

    try pty.setWindowSize(columns: 143, rows: 47)
    try #require(kill(getpid(), SIGWINCH) == 0)
    let event = try #require(try source.nextEvent(timeout: .milliseconds(500)))
    #expect(event == .signal(.windowChanged))
    #expect(try session.handleSignalEvent(.windowChanged) == .readSize)
    #expect(
      try TerminalSizeReader(fileDescriptor: pty.slaveFileDescriptor).read()
        == TerminalSize(columns: 143, rows: 47)
    )

    let stop = try pty.captureOutput(exactByteCount: terminalTestDeactivationBytes.count) {
      try session.stop()
    }
    #expect(try stop.result.get() == .stopped)
    #expect(stop.output == terminalTestDeactivationBytes)
    #expect(try pty.attributesSnapshot() == originalAttributes)
    withExtendedLifetime(source) {}
  }
  #endif

  @Test
  func `Input readiness uses the supplied descriptor`() throws {
    let descriptors = try makePipe()
    defer { closePipe(descriptors) }
    let source = try TerminalEventSource(inputFileDescriptor: descriptors[0])
    var byte: UInt8 = 0x41

    try #require(write(descriptors[1], &byte, 1) == 1)

    #expect(try source.nextEvent(timeout: .milliseconds(500)) == .inputReady)
  }

  @Test
  func `Unread wake requests are coalesced`() throws {
    let descriptors = try makePipe()
    defer { closePipe(descriptors) }
    let source = try TerminalEventSource(inputFileDescriptor: descriptors[0])

    try source.wake()
    try source.wake()
    try source.wake()

    #expect(try source.nextEvent(timeout: .milliseconds(500)) == .wake)
    #expect(try source.nextEvent(timeout: .zero) == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func `A nil timeout blocks until an explicit wake`() throws {
    let descriptors = try makePipe()
    let resultDescriptors = try makePipe()
    defer {
      closePipe(descriptors)
      closePipe(resultDescriptors)
    }
    let source = try TerminalEventSource(inputFileDescriptor: descriptors[0])
    let started = DispatchSemaphore(value: 0)
    let finished = DispatchGroup()
    let waitQueue = DispatchQueue(label: "TermKitTests.blocking-wait")
    finished.enter()
    waitQueue.async {
      started.signal()
      var resultByte: UInt8
      do {
        let event = try source.nextEvent(timeout: nil)
        resultByte = event == .wake ? 1 : 2
      } catch {
        resultByte = 255
      }
      _ = write(resultDescriptors[1], &resultByte, 1)
      finished.leave()
    }

    try #require(started.wait(timeout: .now() + 1) == .success)
    var resultPoll = pollfd(fd: resultDescriptors[0], events: Int16(POLLIN), revents: 0)
    #expect(poll(&resultPoll, 1, 0) == 0)
    try source.wake()
    try #require(finished.wait(timeout: .now() + 1) == .success)
    waitQueue.sync {}

    var resultByte: UInt8 = 0
    try #require(read(resultDescriptors[0], &resultByte, 1) == 1)
    #expect(resultByte == 1)
    withExtendedLifetime(waitQueue) {}
  }

  @Test
  func `Only one source can own signal handlers`() throws {
    let firstPipe = try makePipe()
    let secondPipe = try makePipe()
    defer {
      closePipe(firstPipe)
      closePipe(secondPipe)
    }
    let source = try TerminalEventSource(inputFileDescriptor: firstPipe[0])

    #expect(throws: TerminalEventSourceError.activeSourceExists) {
      _ = try TerminalEventSource(inputFileDescriptor: secondPipe[0])
    }
    withExtendedLifetime(source) {}
  }

  @Test
  func `Signals map to events and previous handlers are restored`() throws {
    let descriptors = try makePipe()
    defer { closePipe(descriptors) }
    let signalNumbers = [SIGINT, SIGTERM, SIGQUIT, SIGHUP, SIGTSTP, SIGCONT, SIGWINCH]
    let previousActions = try signalNumbers.map(readSignalAction)
    var source: TerminalEventSource? = try TerminalEventSource(inputFileDescriptor: descriptors[0])

    try #require(kill(getpid(), SIGWINCH) == 0)
    #expect(try source?.nextEvent(timeout: .milliseconds(500)) == .signal(.windowChanged))
    source = nil

    let restoredActions = try signalNumbers.map(readSignalAction)
    for (previous, restored) in zip(previousActions, restoredActions) {
      #expect(terminalTestSignalHandlerAddress(previous) == terminalTestSignalHandlerAddress(restored))
      #expect(previous.sa_flags == restored.sa_flags)
      for signalNumber in signalNumbers {
        var previousMask = previous.sa_mask
        var restoredMask = restored.sa_mask
        #expect(
          sigismember(&previousMask, signalNumber)
            == sigismember(&restoredMask, signalNumber)
        )
      }
    }
  }

  #if canImport(Darwin) || canImport(Glibc)
  @Test
  func `Termination signal restores PTY state through the event source`() throws {
    let pty = try PTYPair()
    let originalAttributes = try pty.attributesSnapshot()
    let session = TerminalSession(transport: makeTerminalTestTransport(pty: pty))
    let start = try pty.captureOutput(exactByteCount: terminalTestActivationBytes.count) {
      try session.start()
    }
    #expect(try start.result.get() == .started)
    var source: TerminalEventSource? = try TerminalEventSource(inputFileDescriptor: pty.slaveFileDescriptor)

    try #require(kill(getpid(), SIGTERM) == 0)
    #expect(try source?.nextEvent(timeout: .milliseconds(500)) == .signal(.terminate))
    let stop = try pty.captureOutput(exactByteCount: terminalTestDeactivationBytes.count) {
      try session.handleSignalEvent(.terminate)
    }
    #expect(try stop.result.get() == .terminate)
    #expect(stop.output == terminalTestDeactivationBytes)
    #expect(session.state == .inactive)
    #expect(try pty.attributesSnapshot() == originalAttributes)
    source = nil
  }

  @Test
  func `Suspend and resume signals restore and reactivate a PTY session`() throws {
    let pty = try PTYPair()
    let originalAttributes = try pty.attributesSnapshot()
    let session = TerminalSession(transport: makeTerminalTestTransport(pty: pty))
    let start = try pty.captureOutput(exactByteCount: terminalTestActivationBytes.count) {
      try session.start()
    }
    #expect(try start.result.get() == .started)
    let source = try TerminalEventSource(inputFileDescriptor: pty.slaveFileDescriptor)

    try #require(kill(getpid(), SIGTSTP) == 0)
    #expect(try source.nextEvent(timeout: .milliseconds(500)) == .signal(.suspend))
    let suspend = try pty.captureOutput(exactByteCount: terminalTestDeactivationBytes.count) {
      try session.handleSignalEvent(.suspend)
    }
    #expect(try suspend.result.get() == .suspendProcess)
    #expect(session.state == .suspended)
    #expect(try pty.attributesSnapshot() == originalAttributes)

    try #require(kill(getpid(), SIGCONT) == 0)
    #expect(try source.nextEvent(timeout: .milliseconds(500)) == .signal(.resume))
    let resume = try pty.captureOutput(exactByteCount: terminalTestActivationBytes.count) {
      try session.handleSignalEvent(.resume)
    }
    #expect(try resume.result.get() == .resumed(requiresFullRepaint: true))
    #expect(session.state == .active)

    let stop = try pty.captureOutput(exactByteCount: terminalTestDeactivationBytes.count) {
      try session.stop()
    }
    #expect(try stop.result.get() == .stopped)
    #expect(try pty.attributesSnapshot() == originalAttributes)
  }
  #endif

  private func makePipe() throws -> [Int32] {
    var descriptors: [Int32] = [-1, -1]
    try #require(pipe(&descriptors) == 0)
    return descriptors
  }

  private func closePipe(_ descriptors: [Int32]) {
    _ = close(descriptors[0])
    _ = close(descriptors[1])
  }

  private func readSignalAction(_ signalNumber: Int32) throws -> sigaction {
    var action = sigaction()
    try #require(sigaction(signalNumber, nil, &action) == 0)
    return action
  }
}
