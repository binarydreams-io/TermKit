#if canImport(Darwin) || canImport(Glibc)
import Foundation
import Dispatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum PTYTestError: Error {
    case posix(operation: String, errorCode: Int32)
    case timedOut(expectedByteCount: Int, receivedByteCount: Int)
    case endOfFile(expectedByteCount: Int, receivedByteCount: Int)
}

struct TerminalAttributesSnapshot: Equatable {
    let inputFlags: tcflag_t
    let outputFlags: tcflag_t
    let controlFlags: tcflag_t
    let localFlags: tcflag_t
    let inputSpeed: speed_t
    let outputSpeed: speed_t
    let controlCharacters: [cc_t]

    init(_ attributes: inout termios) {
        inputFlags = attributes.c_iflag
        outputFlags = attributes.c_oflag
        controlFlags = attributes.c_cflag
        localFlags = attributes.c_lflag
        inputSpeed = cfgetispeed(&attributes)
        outputSpeed = cfgetospeed(&attributes)
        controlCharacters = withUnsafePointer(to: &attributes.c_cc) { pointer in
            pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { characters in
                Array(UnsafeBufferPointer(start: characters, count: Int(NCCS)))
            }
        }
    }
}

final class PTYPair: @unchecked Sendable {
    let masterFileDescriptor: Int32
    let slaveFileDescriptor: Int32

    private static let nameLock = NSLock()

    init() throws {
        let master = terminalTestsPosixOpenpt(O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard master >= 0 else {
            throw PTYTestError.posix(operation: "posix_openpt", errorCode: errno)
        }

        do {
            try Self.setCloseOnExec(master)
            guard terminalTestsGrantpt(master) == 0 else {
                throw PTYTestError.posix(operation: "grantpt", errorCode: errno)
            }
            guard terminalTestsUnlockpt(master) == 0 else {
                throw PTYTestError.posix(operation: "unlockpt", errorCode: errno)
            }

            let slaveName = try Self.slaveName(for: master)
            let slave = open(slaveName, O_RDWR | O_NOCTTY)
            guard slave >= 0 else {
                throw PTYTestError.posix(operation: "open", errorCode: errno)
            }

            do {
                try Self.setCloseOnExec(slave)
            } catch {
                _ = close(slave)
                throw error
            }

            masterFileDescriptor = master
            slaveFileDescriptor = slave
        } catch {
            _ = close(master)
            throw error
        }
    }

    deinit {
        _ = close(slaveFileDescriptor)
        _ = close(masterFileDescriptor)
    }

    func attributes() throws -> termios {
        var attributes = termios()
        guard tcgetattr(slaveFileDescriptor, &attributes) == 0 else {
            throw PTYTestError.posix(operation: "tcgetattr", errorCode: errno)
        }
        return attributes
    }

    func attributesSnapshot() throws -> TerminalAttributesSnapshot {
        var attributes = try attributes()
        return TerminalAttributesSnapshot(&attributes)
    }

    func setWindowSize(columns: UInt16, rows: UInt16) throws {
        var size = winsize()
        size.ws_row = rows
        size.ws_col = columns
        #if canImport(Darwin)
        let result = Darwin.ioctl(slaveFileDescriptor, TIOCSWINSZ, &size)
        #else
        let result = Glibc.ioctl(slaveFileDescriptor, UInt(TIOCSWINSZ), &size)
        #endif
        guard result == 0 else {
            throw PTYTestError.posix(operation: "ioctl(TIOCSWINSZ)", errorCode: errno)
        }
    }

    func writeToMaster(_ bytes: [UInt8], timeoutMilliseconds: Int32 = 1_000) throws {
        guard bytes.isEmpty == false else { return }
        let deadline = try monotonicMilliseconds() + UInt64(timeoutMilliseconds)

        try bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var writtenByteCount = 0
            while writtenByteCount < buffer.count {
                let result = platformWrite(
                    masterFileDescriptor,
                    baseAddress.advanced(by: writtenByteCount),
                    buffer.count - writtenByteCount
                )
                if result > 0 {
                    writtenByteCount += result
                    continue
                }
                if result < 0, errno == EINTR { continue }
                if result < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    try wait(for: Int16(POLLOUT), deadline: deadline)
                    continue
                }
                throw PTYTestError.posix(operation: "write", errorCode: result == 0 ? EIO : errno)
            }
        }
    }

    func readFromMaster(exactByteCount: Int, timeoutMilliseconds: Int32 = 1_000) throws -> [UInt8] {
        var received: [UInt8] = []
        received.reserveCapacity(exactByteCount)
        let deadline = try monotonicMilliseconds() + UInt64(timeoutMilliseconds)

        while received.count < exactByteCount {
            try wait(
                for: Int16(POLLIN),
                deadline: deadline,
                expectedByteCount: exactByteCount,
                receivedByteCount: received.count
            )
            var buffer = [UInt8](repeating: 0, count: exactByteCount - received.count)
            let result = buffer.withUnsafeMutableBytes { bytes in
                platformRead(masterFileDescriptor, bytes.baseAddress, bytes.count)
            }
            if result > 0 {
                received.append(contentsOf: buffer.prefix(result))
                continue
            }
            if result == 0 {
                throw PTYTestError.endOfFile(
                    expectedByteCount: exactByteCount,
                    receivedByteCount: received.count
                )
            }
            if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
            throw PTYTestError.posix(operation: "read", errorCode: errno)
        }
        return received
    }

    func captureOutput<Value>(
        exactByteCount: Int,
        timeoutMilliseconds: Int32 = 1_000,
        while operation: () throws -> Value
    ) throws -> (result: Result<Value, any Error>, output: [UInt8]) {
        let readResult = PTYReadResult()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { [self] in
            readResult.store(
                Result {
                    try readFromMaster(
                        exactByteCount: exactByteCount,
                        timeoutMilliseconds: timeoutMilliseconds
                    )
                }
            )
            finished.signal()
        }

        let operationResult = Result { try operation() }
        guard finished.wait(timeout: .now() + .milliseconds(Int(timeoutMilliseconds) + 250)) == .success else {
            throw PTYTestError.timedOut(
                expectedByteCount: exactByteCount,
                receivedByteCount: 0
            )
        }
        return (operationResult, try readResult.get())
    }

    private func wait(
        for events: Int16,
        deadline: UInt64,
        expectedByteCount: Int = 0,
        receivedByteCount: Int = 0
    ) throws {
        while true {
            let now = try monotonicMilliseconds()
            guard now < deadline else {
                throw PTYTestError.timedOut(
                    expectedByteCount: expectedByteCount,
                    receivedByteCount: receivedByteCount
                )
            }
            let remaining = min(deadline - now, UInt64(Int32.max))
            var descriptor = pollfd(fd: masterFileDescriptor, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(remaining))
            if result > 0 {
                if Int32(descriptor.revents) & Int32(events) != 0 { return }
                throw PTYTestError.posix(operation: "poll", errorCode: EIO)
            }
            if result == 0 {
                throw PTYTestError.timedOut(
                    expectedByteCount: expectedByteCount,
                    receivedByteCount: receivedByteCount
                )
            }
            if errno == EINTR { continue }
            throw PTYTestError.posix(operation: "poll", errorCode: errno)
        }
    }

    private static func slaveName(for masterFileDescriptor: Int32) throws -> String {
        nameLock.lock()
        defer { nameLock.unlock() }
        guard let name = terminalTestsPtsname(masterFileDescriptor) else {
            throw PTYTestError.posix(operation: "ptsname", errorCode: errno)
        }
        return String(cString: name)
    }

    private static func setCloseOnExec(_ fileDescriptor: Int32) throws {
        let flags = fcntl(fileDescriptor, F_GETFD)
        guard flags >= 0 else {
            throw PTYTestError.posix(operation: "fcntl(F_GETFD)", errorCode: errno)
        }
        guard fcntl(fileDescriptor, F_SETFD, flags | FD_CLOEXEC) == 0 else {
            throw PTYTestError.posix(operation: "fcntl(F_SETFD)", errorCode: errno)
        }
    }
}

private final class PTYReadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<[UInt8], any Error>?

    func store(_ result: Result<[UInt8], any Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() throws -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        guard let result else {
            throw PTYTestError.timedOut(expectedByteCount: 0, receivedByteCount: 0)
        }
        return try result.get()
    }
}

func terminalControlCharacter(_ index: Int32, in attributes: inout termios) -> cc_t {
    withUnsafePointer(to: &attributes.c_cc) { pointer in
        pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { characters in
            characters[Int(index)]
        }
    }
}

private func monotonicMilliseconds() throws -> UInt64 {
    var time = timespec()
    guard clock_gettime(CLOCK_MONOTONIC, &time) == 0 else {
        throw PTYTestError.posix(operation: "clock_gettime", errorCode: errno)
    }
    return UInt64(time.tv_sec) * 1_000 + UInt64(time.tv_nsec) / 1_000_000
}

private func platformRead(_ fileDescriptor: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
    #if canImport(Darwin)
    Darwin.read(fileDescriptor, buffer, count)
    #else
    Glibc.read(fileDescriptor, buffer, count)
    #endif
}

private func platformWrite(_ fileDescriptor: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
    #if canImport(Darwin)
    Darwin.write(fileDescriptor, buffer, count)
    #else
    Glibc.write(fileDescriptor, buffer, count)
    #endif
}

@_silgen_name("posix_openpt")
private func terminalTestsPosixOpenpt(_ flags: Int32) -> Int32

@_silgen_name("grantpt")
private func terminalTestsGrantpt(_ fileDescriptor: Int32) -> Int32

@_silgen_name("unlockpt")
private func terminalTestsUnlockpt(_ fileDescriptor: Int32) -> Int32

@_silgen_name("ptsname")
private func terminalTestsPtsname(_ fileDescriptor: Int32) -> UnsafeMutablePointer<CChar>?
#endif
