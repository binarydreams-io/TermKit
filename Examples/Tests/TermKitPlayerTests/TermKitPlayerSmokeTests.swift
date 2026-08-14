import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Darwin) || canImport(Glibc)
struct TermKitPlayerSmokeTests {
  private let activation = "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[?1000h\u{1B}[?1006h\u{1B}[?1004h"
  private let restoration =
    "\u{1B}[?1004l"
      + "\u{1B}[?9l\u{1B}[?1000l\u{1B}[?1001l\u{1B}[?1002l\u{1B}[?1003l"
      + "\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l"
      + "\u{1B}[?2004l\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l"

  @Test(.timeLimit(.minutes(1)))
  func `Player starts, handles input and resize, and restores a PTY`() throws {
    let pty = try PTYPair(columns: 120, rows: 32)
    let executable = try testExecutableDirectory()
      .appendingPathComponent("TermKitPlayer")
    let harness = try testExecutableDirectory()
      .appendingPathComponent("TermKitPlayerPTYHarness")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw SmokeError.missingExecutable(executable.path)
    }
    guard FileManager.default.isExecutableFile(atPath: harness.path) else {
      throw SmokeError.missingExecutable(harness.path)
    }

    let processID = try pty.spawn(harness: harness, executable: executable)
    defer { terminateAndReap(processID) }
    var output = try pty.readUntil(operation: "waiting for full player frame", timeoutMilliseconds: 10000) { bytes in
      guard let text = String(bytes: bytes, encoding: .utf8) else { return false }
      return text.contains("FULL DECK // TK-97")
    }

    try pty.writeToMaster(Array(" ".utf8), timeoutMilliseconds: 1000)
    output += try pty.readUntil(operation: "waiting for play input frame", timeoutMilliseconds: 5000) { bytes in
      bytes.isEmpty == false
    }
    try pty.writeToMaster(Array("m".utf8), timeoutMilliseconds: 1000)
    output += try pty.readUntil(operation: "waiting for mute input frame", timeoutMilliseconds: 5000) { bytes in
      bytes.isEmpty == false
    }
    try pty.writeToMaster(Array(" ".utf8), timeoutMilliseconds: 1000)
    output += try pty.readUntil(operation: "waiting for pause input frame", timeoutMilliseconds: 5000) { bytes in
      bytes.isEmpty == false
    }
    try pty.resize(columns: 56, rows: 18)
    guard kill(processID, SIGWINCH) == 0 else { throw SmokeError.posix("kill(SIGWINCH)", errno) }
    output += try pty.readUntil(operation: "waiting for compact player frame", timeoutMilliseconds: 5000) { bytes in
      bytes.isEmpty == false
    }
    try pty.resize(columns: 40, rows: 16)
    guard kill(processID, SIGWINCH) == 0 else { throw SmokeError.posix("kill(SIGWINCH)", errno) }
    output += try pty.readUntil(operation: "waiting for minimum player frame", timeoutMilliseconds: 5000) { bytes in
      bytes.isEmpty == false
    }
    try pty.writeToMaster(Array("q".utf8), timeoutMilliseconds: 1000)
    output += try pty.readUntil(operation: "waiting for terminal restoration", timeoutMilliseconds: 5000) { bytes in
      String(decoding: bytes, as: UTF8.self).contains(restoration)
    }
    let exitCode = try waitForExit(processID, timeoutMilliseconds: 5000)
    output += try pty.readRemaining(timeoutMilliseconds: 1000)
    let text = String(decoding: output, as: UTF8.self)

    #expect(exitCode == 0)
    #expect(text.contains("FULL DECK // TK-97"))
    #expect(text.contains("Blue Hour Relay"))
    #expect(text.contains("PAUSED"))
    #expect(text.contains("QUEUE"))
    #expect(text.contains("no audio output"))
    let activationRange = try #require(text.range(of: activation))
    let restorationRange = try #require(text.range(of: restoration))
    #expect(activationRange.lowerBound < restorationRange.lowerBound)
  }
}

private enum SmokeError: Error, CustomStringConvertible {
  case missingExecutable(String)
  case posix(String, Int32)
  case processExitedBeforeFrame
  case timedOut(String)

  var description: String {
    switch self {
    case let .missingExecutable(path): "Missing built showcase executable at \(path)"
    case let .posix(operation, code): "\(operation) failed with errno \(code)"
    case .processExitedBeforeFrame: "Showcase exited before rendering its first frame"
    case let .timedOut(operation): "Timed out while \(operation)"
    }
  }
}

private final class PTYPair {
  let master: Int32
  let slave: Int32
  let slavePath: String

  init(columns: UInt16, rows: UInt16) throws {
    self.master = showcasePosixOpenpt(O_RDWR | O_NOCTTY | O_NONBLOCK)
    guard master >= 0 else { throw SmokeError.posix("posix_openpt", errno) }
    do {
      guard showcaseGrantpt(master) == 0 else { throw SmokeError.posix("grantpt", errno) }
      guard showcaseUnlockpt(master) == 0 else { throw SmokeError.posix("unlockpt", errno) }
      guard let slaveName = showcasePtsname(master) else { throw SmokeError.posix("ptsname", errno) }
      let slaveNameBytes = UnsafeRawPointer(slaveName).assumingMemoryBound(to: UInt8.self)
      self.slavePath = String(
        decoding: UnsafeBufferPointer(start: slaveNameBytes, count: strlen(slaveName)),
        as: UTF8.self
      )
      self.slave = open(slaveName, O_RDWR | O_NOCTTY)
      guard slave >= 0 else { throw SmokeError.posix("open", errno) }
      var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
      #if canImport(Darwin)
      let result = Darwin.ioctl(slave, TIOCSWINSZ, &size)
      #else
      let result = Glibc.ioctl(slave, UInt(TIOCSWINSZ), &size)
      #endif
      guard result == 0 else { throw SmokeError.posix("ioctl(TIOCSWINSZ)", errno) }
    } catch {
      _ = close(master)
      throw error
    }
  }

  deinit {
    _ = close(slave)
    _ = close(master)
  }

  func spawn(harness: URL, executable: URL) throws -> pid_t {
    let environment = ProcessInfo.processInfo.environment
      .merging(["TERM": "xterm-256color"]) { _, new in new }
      .map { "\($0.key)=\($0.value)" }
      .sorted()
    var processID = pid_t()
    let status = try withCStringArray([
      harness.path,
      slavePath,
      executable.path,
      String(master),
      String(slave)
    ]) { arguments in
      try withCStringArray(environment) { environment in
        harness.path.withCString {
          posix_spawn(&processID, $0, nil, nil, arguments, environment)
        }
      }
    }
    guard status == 0 else { throw SmokeError.posix("posix_spawn", status) }
    return processID
  }

  func writeToMaster(_ bytes: [UInt8], timeoutMilliseconds: Int32) throws {
    let deadline = monotonicMilliseconds() + UInt64(timeoutMilliseconds)
    var offset = 0
    while offset < bytes.count {
      let result = bytes.withUnsafeBytes { buffer in
        write(master, buffer.baseAddress?.advanced(by: offset), buffer.count - offset)
      }
      if result > 0 {
        offset += result
        continue
      }
      if result < 0, errno == EINTR {
        continue
      }
      if result < 0, errno == EAGAIN || errno == EWOULDBLOCK {
        try waitForMaster(events: Int16(POLLOUT), deadline: deadline, operation: "writing PTY input")
        continue
      }
      throw SmokeError.posix("write", errno)
    }
  }

  func resize(columns: UInt16, rows: UInt16) throws {
    var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
    #if canImport(Darwin)
    let result = Darwin.ioctl(slave, TIOCSWINSZ, &size)
    #else
    let result = Glibc.ioctl(slave, UInt(TIOCSWINSZ), &size)
    #endif
    guard result == 0 else { throw SmokeError.posix("ioctl(TIOCSWINSZ)", errno) }
  }

  func readUntil(
    operation: String = "waiting for player frame",
    timeoutMilliseconds: Int32,
    condition: ([UInt8]) -> Bool
  ) throws -> [UInt8] {
    let deadline = monotonicMilliseconds() + UInt64(timeoutMilliseconds)
    var output: [UInt8] = []
    while condition(output) == false {
      do {
        try waitForMaster(events: Int16(POLLIN), deadline: deadline, operation: operation)
      } catch SmokeError.timedOut {
        let suffix = String(decoding: output.suffix(512), as: UTF8.self)
        throw SmokeError.timedOut("\(operation); output suffix: \(suffix)")
      }
      guard try appendAvailable(to: &output) else { throw SmokeError.processExitedBeforeFrame }
    }
    return output
  }

  func readRemaining(timeoutMilliseconds: Int32) throws -> [UInt8] {
    let deadline = monotonicMilliseconds() + UInt64(timeoutMilliseconds)
    var output: [UInt8] = []
    while monotonicMilliseconds() < deadline {
      var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
      let result = poll(&descriptor, 1, 20)
      if result > 0 {
        if try appendAvailable(to: &output) == false {
          break
        }
      } else if result < 0, errno != EINTR {
        throw SmokeError.posix("poll", errno)
      }
    }
    return output
  }

  private func appendAvailable(to output: inout [UInt8]) throws -> Bool {
    var buffer = [UInt8](repeating: 0, count: 16384)
    let result = buffer.withUnsafeMutableBytes { read(master, $0.baseAddress, $0.count) }
    if result > 0 {
      output.append(contentsOf: buffer.prefix(result))
      return true
    }
    if result < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
      return true
    }
    if result == 0 || errno == EIO {
      return false
    }
    throw SmokeError.posix("read", errno)
  }

  private func waitForMaster(events: Int16, deadline: UInt64, operation: String) throws {
    while true {
      let now = monotonicMilliseconds()
      guard now < deadline else { throw SmokeError.timedOut(operation) }
      var descriptor = pollfd(fd: master, events: events, revents: 0)
      let result = poll(&descriptor, 1, Int32(min(deadline - now, UInt64(Int32.max))))
      if result > 0, descriptor.revents & events != 0 {
        return
      }
      if result == 0 {
        throw SmokeError.timedOut(operation)
      }
      if result < 0, errno == EINTR {
        continue
      }
      if result > 0, descriptor.revents & Int16(POLLHUP) != 0 {
        throw SmokeError.processExitedBeforeFrame
      }
      throw SmokeError.posix("poll", errno)
    }
  }
}

private func waitForExit(_ processID: pid_t, timeoutMilliseconds: Int32) throws -> Int32 {
  let deadline = monotonicMilliseconds() + UInt64(timeoutMilliseconds)
  var status = Int32()
  while monotonicMilliseconds() < deadline {
    let result = waitpid(processID, &status, WNOHANG)
    if result == processID {
      return status & 0x7F == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F)
    }
    if result < 0, errno != EINTR {
      throw SmokeError.posix("waitpid", errno)
    }
    usleep(10000)
  }
  throw SmokeError.timedOut("waiting for showcase exit")
}

private func terminateAndReap(_ processID: pid_t) {
  _ = kill(processID, SIGKILL)
  var status = Int32()
  while waitpid(processID, &status, 0) < 0, errno == EINTR {}
}

private func monotonicMilliseconds() -> UInt64 {
  var time = timespec()
  precondition(clock_gettime(CLOCK_MONOTONIC, &time) == 0)
  return UInt64(time.tv_sec) * 1000 + UInt64(time.tv_nsec) / 1000000
}

private func testExecutableDirectory() throws -> URL {
  #if canImport(Darwin)
  return Bundle(for: TestBundleMarker.self).bundleURL.deletingLastPathComponent()
  #else
  var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
  let count = readlink("/proc/self/exe", &buffer, buffer.count - 1)
  guard count >= 0 else { throw SmokeError.posix("readlink", errno) }
  return URL(fileURLWithPath: String(decoding: buffer.prefix(count).map(UInt8.init), as: UTF8.self))
    .deletingLastPathComponent()
  #endif
}

#if canImport(Darwin)
private final class TestBundleMarker: NSObject {}
#endif

private func withCStringArray<Result>(
  _ strings: [String],
  body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
) throws -> Result {
  var pointers = strings.map { strdup($0) }
  defer {
    for pointer in pointers {
      free(pointer)
    }
  }
  pointers.append(nil)
  return try pointers.withUnsafeMutableBufferPointer { buffer in
    try body(buffer.baseAddress!)
  }
}

@_silgen_name("posix_openpt")
private func showcasePosixOpenpt(_ flags: Int32) -> Int32

@_silgen_name("grantpt")
private func showcaseGrantpt(_ fileDescriptor: Int32) -> Int32

@_silgen_name("unlockpt")
private func showcaseUnlockpt(_ fileDescriptor: Int32) -> Int32

@_silgen_name("ptsname")
private func showcasePtsname(_ fileDescriptor: Int32) -> UnsafeMutablePointer<CChar>?

#endif
