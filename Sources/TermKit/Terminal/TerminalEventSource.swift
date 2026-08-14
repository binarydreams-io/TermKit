#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
    import Synchronization
#endif

/// An event that wakes the terminal runtime.
public enum TerminalRuntimeEvent: Equatable, Sendable {
    /// The input descriptor can be read without blocking.
    case inputReady

    /// The input descriptor reached end of file.
    case inputClosed

    /// Application code requested a runtime wake.
    case wake

    /// A terminal lifecycle signal was received.
    case signal(TerminalSignalEvent)
}

/// A POSIX operation used by a terminal event source.
public enum TerminalEventSourceOperation: Equatable, Sendable {
    /// Creates the self-pipe.
    case createPipe
    /// Reads descriptor flags.
    case getDescriptorFlags
    /// Writes descriptor flags.
    case setDescriptorFlags
    /// Installs a process signal handler.
    case installSignalHandler
    /// Reads the monotonic clock.
    case readMonotonicClock
    /// Polls event descriptors.
    case poll
    /// Reads the self-pipe.
    case readSelfPipe
    /// Writes the self-pipe.
    case writeSelfPipe
}

/// A terminal event source failure.
public enum TerminalEventSourceError: Error, Equatable, Sendable {
    /// Another source owns the process signal handlers.
    case activeSourceExists

    /// A POSIX call failed.
    case posix(operation: TerminalEventSourceOperation, errorCode: Int32)

    /// A polled descriptor reported an unrecoverable state.
    case descriptorFailure(fileDescriptor: Int32, events: Int16)

    /// A self-pipe write completed without writing its byte.
    case stalledSelfPipeWrite
}

/// Blocks until terminal input, an explicit wake, or a process signal arrives.
public final class TerminalEventSource: Sendable {
    private let owner: TerminalEventSourcePOSIXOwner

    /// Creates a source and installs the terminal lifecycle signal handlers.
    ///
    /// Only one source can own the process signal handlers at a time.
    public init(inputFileDescriptor: Int32 = STDIN_FILENO) throws {
        owner = try TerminalEventSourcePOSIXOwner.make(inputFileDescriptor: inputFileDescriptor)
    }

    /// Returns the next event, or `nil` after a finite timeout expires.
    ///
    /// A `nil` timeout waits indefinitely and does not create a timer.
    public func nextEvent(timeout: TimeSpan? = nil) throws -> TerminalRuntimeEvent? {
        try owner.nextEvent(timeout: timeout)
    }

    /// Wakes a blocked event source.
    ///
    /// Multiple unread wake requests use one byte in the self-pipe.
    public func wake() throws {
        try owner.wake()
    }

    func fillSelfPipeForTesting() throws {
        try owner.fillSelfPipeForTesting()
    }
}

private struct TerminalSignalRegistration {
    let number: Int32
    let previousAction: sigaction
}

private struct TerminalSignalOwnershipState: Sendable {
    var nextToken: UInt64 = 1
    var activeToken: UInt64?
}

private struct TerminalWakeState: Sendable {
    var isPending = false
    var hasNoByte = false
}

/// Protects process-wide signal ownership with a shared lock.
private final class TerminalSignalOwnership: Sendable {
    static let shared = TerminalSignalOwnership()

    private let state = LockedState(TerminalSignalOwnershipState())

    func claim() throws -> UInt64 {
        try state.withLock { state in
            guard state.activeToken == nil else {
                throw TerminalEventSourceError.activeSourceExists
            }
            let token = state.nextToken
            state.nextToken &+= 1
            state.activeToken = token
            return token
        }
    }

    func release(_ token: UInt64) {
        state.withLock { state in
            guard state.activeToken == token else { return }
            state.activeToken = nil
        }
    }
}

#if canImport(Darwin)
    nonisolated(unsafe) private var terminalSignalWriteFileDescriptor: Int32 = -1
    nonisolated(unsafe) private var terminalSignalActiveHandlerCount: Int32 = 0
    nonisolated(unsafe) private var terminalSignalPendingBits: Int32 = 0
#else
    private enum TerminalSignalPipe {
        static let writeFileDescriptor = Atomic<Int32>(-1)
        static let activeHandlerCount = Atomic<Int32>(0)
        static let pendingBits = Atomic<Int32>(0)
    }
#endif

private let terminalManagedSignals: [Int32] = [
    SIGINT,
    SIGTERM,
    SIGQUIT,
    SIGHUP,
    SIGTSTP,
    SIGCONT,
    SIGWINCH,
]

private func terminalEventSignalHandler(_ signalNumber: Int32) {
    let fileDescriptor = enterTerminalSignalHandler()
    if fileDescriptor >= 0 {
        markTerminalSignalPending(signalNumber)
        var byte: UInt8 = 1
        _ = platformWrite(fileDescriptor, &byte, 1)
    }
    leaveTerminalSignalHandler()
}

/// Owns immutable descriptors and synchronizes all mutable POSIX state.
///
/// Locks protect the pending event list, wake state, and the single
/// poll caller. Lock-free atomics protect signal teardown. These rules make
/// this unchecked conformance thread-safe.
private final class TerminalEventSourcePOSIXOwner: @unchecked Sendable {
    private let inputFileDescriptor: Int32
    private let readFileDescriptor: Int32
    private let writeFileDescriptor: Int32
    private let ownershipToken: UInt64
    private let registrations: [TerminalSignalRegistration]
    private let waitLock = LockedState<Void>(())
    private let wakeState = LockedState(TerminalWakeState())
    private var pendingEvents: [TerminalRuntimeEvent] = []
    private var isInputClosed = false

    private init(
        inputFileDescriptor: Int32,
        readFileDescriptor: Int32,
        writeFileDescriptor: Int32,
        ownershipToken: UInt64,
        registrations: [TerminalSignalRegistration]
    ) {
        self.inputFileDescriptor = inputFileDescriptor
        self.readFileDescriptor = readFileDescriptor
        self.writeFileDescriptor = writeFileDescriptor
        self.ownershipToken = ownershipToken
        self.registrations = registrations
    }

    deinit {
        disableTerminalSignalPipe()
        for registration in registrations.reversed() {
            var previousAction = registration.previousAction
            _ = platformSigaction(registration.number, &previousAction, nil)
        }
        waitForTerminalSignalHandlers()
        _ = platformClose(readFileDescriptor)
        _ = platformClose(writeFileDescriptor)
        TerminalSignalOwnership.shared.release(ownershipToken)
    }

    static func make(inputFileDescriptor: Int32) throws -> TerminalEventSourcePOSIXOwner {
        let ownershipToken = try TerminalSignalOwnership.shared.claim()
        var pipeFileDescriptors: [Int32] = [-1, -1]
        guard platformPipe(&pipeFileDescriptors) == 0 else {
            let errorCode = errno
            TerminalSignalOwnership.shared.release(ownershipToken)
            throw TerminalEventSourceError.posix(operation: .createPipe, errorCode: errorCode)
        }

        var registrations: [TerminalSignalRegistration] = []
        do {
            try configurePipeDescriptor(pipeFileDescriptors[0])
            try configurePipeDescriptor(pipeFileDescriptors[1])

            prepareTerminalSignalPipe()
            enableTerminalSignalPipe(fileDescriptor: pipeFileDescriptors[1])

            for signalNumber in terminalManagedSignals {
                registrations.append(try installHandler(for: signalNumber))
            }

            return TerminalEventSourcePOSIXOwner(
                inputFileDescriptor: inputFileDescriptor,
                readFileDescriptor: pipeFileDescriptors[0],
                writeFileDescriptor: pipeFileDescriptors[1],
                ownershipToken: ownershipToken,
                registrations: registrations
            )
        } catch {
            disableTerminalSignalPipe()
            for registration in registrations.reversed() {
                var previousAction = registration.previousAction
                _ = platformSigaction(registration.number, &previousAction, nil)
            }
            waitForTerminalSignalHandlers()
            _ = platformClose(pipeFileDescriptors[0])
            _ = platformClose(pipeFileDescriptors[1])
            TerminalSignalOwnership.shared.release(ownershipToken)
            throw error
        }
    }

    func nextEvent(timeout: TimeSpan?) throws -> TerminalRuntimeEvent? {
        try waitLock.withLock { _ in
            if let event = dequeueEvent() { return event }

            let deadline: UInt64?
            if let timeout {
                let now = try monotonicNanoseconds()
                if timeout.nanoseconds > 0 {
                    let (value, overflow) = now.addingReportingOverflow(UInt64(timeout.nanoseconds))
                    deadline = overflow ? UInt64.max : value
                } else {
                    deadline = now
                }
            } else {
                deadline = nil
            }
            var isFirstPoll = true

            while true {
                let pollTimeout = try pollTimeoutMilliseconds(
                    timeout: timeout,
                    deadline: deadline,
                    isFirstPoll: isFirstPoll
                )
                guard let pollTimeout else { return nil }

                var descriptors = [
                    pollfd(fd: readFileDescriptor, events: Int16(POLLIN), revents: 0),
                    pollfd(
                        fd: isInputClosed ? -1 : inputFileDescriptor,
                        events: Int16(POLLIN),
                        revents: 0
                    ),
                ]
                let result = descriptors.withUnsafeMutableBufferPointer { buffer in
                    platformPoll(buffer.baseAddress, nfds_t(buffer.count), pollTimeout)
                }

                if result == 0 {
                    if timeout != nil {
                        guard let deadline else { return nil }
                        if try monotonicNanoseconds() >= deadline { return nil }
                    }
                    continue
                }
                if result < 0 {
                    let errorCode = errno
                    if errorCode == EINTR { continue }
                    throw TerminalEventSourceError.posix(operation: .poll, errorCode: errorCode)
                }
                isFirstPoll = false

                try processPollResults(descriptors)
                if let event = dequeueEvent() { return event }
            }
        }
    }

    func wake() throws {
        try wakeState.withLock { wakeState in
            guard wakeState.isPending == false else { return }
            wakeState.isPending = true
            wakeState.hasNoByte = false

            var byte: UInt8 = 0
            while true {
                let result = platformWrite(writeFileDescriptor, &byte, 1)
                if result == 1 { return }
                if result == 0 {
                    wakeState.isPending = false
                    throw TerminalEventSourceError.stalledSelfPipeWrite
                }
                let errorCode = errno
                if errorCode == EINTR { continue }
                if errorCode == EAGAIN || errorCode == EWOULDBLOCK {
                    wakeState.hasNoByte = true
                    return
                }
                wakeState.isPending = false
                throw TerminalEventSourceError.posix(operation: .writeSelfPipe, errorCode: errorCode)
            }
        }
    }

    func fillSelfPipeForTesting() throws {
        let bytes = [UInt8](repeating: UInt8.max, count: 1_024)
        while true {
            let result = bytes.withUnsafeBytes { buffer in
                platformWrite(writeFileDescriptor, buffer.baseAddress, buffer.count)
            }
            if result > 0 { continue }
            if result == 0 { throw TerminalEventSourceError.stalledSelfPipeWrite }
            let errorCode = errno
            if errorCode == EINTR { continue }
            if errorCode == EAGAIN || errorCode == EWOULDBLOCK { return }
            throw TerminalEventSourceError.posix(operation: .writeSelfPipe, errorCode: errorCode)
        }
    }

    private func processPollResults(_ descriptors: [pollfd]) throws {
        let selfPipeEvents = descriptors[0].revents
        if hasPollEvent(selfPipeEvents, POLLNVAL | POLLERR | POLLHUP) {
            throw TerminalEventSourceError.descriptorFailure(
                fileDescriptor: readFileDescriptor,
                events: selfPipeEvents
            )
        }
        if hasPollEvent(selfPipeEvents, POLLIN) {
            try drainSelfPipe()
        }

        let inputEvents = descriptors[1].revents
        if hasPollEvent(inputEvents, POLLNVAL) {
            throw TerminalEventSourceError.descriptorFailure(
                fileDescriptor: inputFileDescriptor,
                events: inputEvents
            )
        }
        if hasPollEvent(inputEvents, POLLIN) {
            enqueue(.inputReady)
        } else if hasPollEvent(inputEvents, POLLHUP | POLLERR) {
            isInputClosed = true
            enqueue(.inputClosed)
        }
    }

    private func drainSelfPipe() throws {
        var bytes = [UInt8](repeating: 0, count: 128)
        var foundWakeByte = false

        while true {
            let result = bytes.withUnsafeMutableBytes { buffer in
                platformRead(readFileDescriptor, buffer.baseAddress, buffer.count)
            }
            if result > 0 {
                for byte in bytes.prefix(result) where byte == 0 {
                    foundWakeByte = true
                }
                continue
            }
            if result == 0 {
                throw TerminalEventSourceError.descriptorFailure(
                    fileDescriptor: readFileDescriptor,
                    events: Int16(POLLHUP)
                )
            }

            let errorCode = errno
            if errorCode == EINTR { continue }
            if errorCode == EAGAIN || errorCode == EWOULDBLOCK {
                let shouldDeliverWake = wakeState.withLock { wakeState in
                    foundWakeByte || (wakeState.isPending && wakeState.hasNoByte)
                }
                if shouldDeliverWake {
                    enqueue(.wake)
                }
                enqueuePendingSignals()
                return
            }
            throw TerminalEventSourceError.posix(operation: .readSelfPipe, errorCode: errorCode)
        }
    }

    private func enqueue(_ event: TerminalRuntimeEvent) {
        pendingEvents.append(event)
    }

    private func enqueuePendingSignals() {
        let bits = takeTerminalSignalPendingBits()
        for signalNumber in terminalManagedSignals where bits & terminalSignalBit(signalNumber) != 0 {
            if let signal = TerminalSignalEvent(signalNumber: signalNumber) {
                enqueue(.signal(signal))
            }
        }
    }

    private func dequeueEvent() -> TerminalRuntimeEvent? {
        guard pendingEvents.isEmpty == false else { return nil }
        let event = pendingEvents.removeFirst()
        if event == .wake {
            wakeState.withLock { wakeState in
                wakeState.isPending = false
                wakeState.hasNoByte = false
            }
        }
        return event
    }
}

private func prepareTerminalSignalPipe() {
    _ = takeTerminalSignalPendingBits()
    #if canImport(Glibc)
        _ = TerminalSignalPipe.writeFileDescriptor.load(ordering: .sequentiallyConsistent)
        _ = TerminalSignalPipe.activeHandlerCount.load(ordering: .sequentiallyConsistent)
    #endif
}

private func terminalSignalBit(_ signalNumber: Int32) -> Int32 {
    switch signalNumber {
    case SIGINT: 1 << 0
    case SIGTERM: 1 << 1
    case SIGQUIT: 1 << 2
    case SIGHUP: 1 << 3
    case SIGTSTP: 1 << 4
    case SIGCONT: 1 << 5
    case SIGWINCH: 1 << 6
    default: 0
    }
}

private func markTerminalSignalPending(_ signalNumber: Int32) {
    let bit = terminalSignalBit(signalNumber)
    guard bit != 0 else { return }
    #if canImport(Darwin)
        _ = OSAtomicOr32Barrier(UInt32(bit), &terminalSignalPendingBits)
    #else
        _ = TerminalSignalPipe.pendingBits.bitwiseOr(bit, ordering: .sequentiallyConsistent)
    #endif
}

private func takeTerminalSignalPendingBits() -> Int32 {
    #if canImport(Darwin)
        while true {
            let bits = OSAtomicAdd32Barrier(0, &terminalSignalPendingBits)
            if OSAtomicCompareAndSwap32Barrier(bits, 0, &terminalSignalPendingBits) {
                return bits
            }
        }
    #else
        return TerminalSignalPipe.pendingBits.exchange(0, ordering: .sequentiallyConsistent)
    #endif
}

private func enterTerminalSignalHandler() -> Int32 {
    #if canImport(Darwin)
        _ = OSAtomicIncrement32Barrier(&terminalSignalActiveHandlerCount)
        return OSAtomicAdd32Barrier(0, &terminalSignalWriteFileDescriptor)
    #else
        _ = TerminalSignalPipe.activeHandlerCount.wrappingAdd(
            1,
            ordering: .sequentiallyConsistent
        )
        return TerminalSignalPipe.writeFileDescriptor.load(ordering: .sequentiallyConsistent)
    #endif
}

private func leaveTerminalSignalHandler() {
    #if canImport(Darwin)
        _ = OSAtomicDecrement32Barrier(&terminalSignalActiveHandlerCount)
    #else
        _ = TerminalSignalPipe.activeHandlerCount.wrappingSubtract(
            1,
            ordering: .sequentiallyConsistent
        )
    #endif
}

private func enableTerminalSignalPipe(fileDescriptor: Int32) {
    #if canImport(Darwin)
        terminalSignalWriteFileDescriptor = fileDescriptor
    #else
        TerminalSignalPipe.writeFileDescriptor.store(
            fileDescriptor,
            ordering: .sequentiallyConsistent
        )
    #endif
}

private func disableTerminalSignalPipe() {
    #if canImport(Darwin)
        while true {
            let oldValue = OSAtomicAdd32Barrier(0, &terminalSignalWriteFileDescriptor)
            if OSAtomicCompareAndSwap32Barrier(
                oldValue,
                -1,
                &terminalSignalWriteFileDescriptor
            ) {
                return
            }
        }
    #else
        TerminalSignalPipe.writeFileDescriptor.store(-1, ordering: .sequentiallyConsistent)
    #endif
}

private func waitForTerminalSignalHandlers() {
    while true {
        #if canImport(Darwin)
            let activeHandlerCount = OSAtomicAdd32Barrier(0, &terminalSignalActiveHandlerCount)
        #else
            let activeHandlerCount = TerminalSignalPipe.activeHandlerCount.load(
                ordering: .sequentiallyConsistent
            )
        #endif
        if activeHandlerCount == 0 { return }
        platformYield()
    }
}

private func configurePipeDescriptor(_ fileDescriptor: Int32) throws {
    let statusFlags = try getDescriptorFlags(fileDescriptor, command: F_GETFL)
    try setDescriptorFlags(fileDescriptor, command: F_SETFL, flags: statusFlags | O_NONBLOCK)

    let descriptorFlags = try getDescriptorFlags(fileDescriptor, command: F_GETFD)
    try setDescriptorFlags(fileDescriptor, command: F_SETFD, flags: descriptorFlags | FD_CLOEXEC)
}

private func getDescriptorFlags(_ fileDescriptor: Int32, command: Int32) throws -> Int32 {
    while true {
        let result = fcntl(fileDescriptor, command)
        if result >= 0 { return result }
        let errorCode = errno
        if errorCode == EINTR { continue }
        throw TerminalEventSourceError.posix(operation: .getDescriptorFlags, errorCode: errorCode)
    }
}

private func setDescriptorFlags(_ fileDescriptor: Int32, command: Int32, flags: Int32) throws {
    while true {
        let result = fcntl(fileDescriptor, command, flags)
        if result == 0 { return }
        let errorCode = errno
        if errorCode == EINTR { continue }
        throw TerminalEventSourceError.posix(operation: .setDescriptorFlags, errorCode: errorCode)
    }
}

private func installHandler(for signalNumber: Int32) throws -> TerminalSignalRegistration {
    var action = sigaction()
    setSignalHandler(&action, terminalEventSignalHandler)
    action.sa_flags = 0
    sigemptyset(&action.sa_mask)

    var previousAction = sigaction()
    guard platformSigaction(signalNumber, &action, &previousAction) == 0 else {
        throw TerminalEventSourceError.posix(operation: .installSignalHandler, errorCode: errno)
    }
    return TerminalSignalRegistration(number: signalNumber, previousAction: previousAction)
}

private func setSignalHandler(
    _ action: inout sigaction,
    _ handler: @escaping @convention(c) (Int32) -> Void
) {
    #if canImport(Darwin)
        action.__sigaction_u.__sa_handler = handler
    #else
        action.__sigaction_handler.sa_handler = handler
    #endif
}

private func pollTimeoutMilliseconds(
    timeout: TimeSpan?,
    deadline: UInt64?,
    isFirstPoll: Bool
) throws -> Int32? {
    guard let timeout else { return -1 }
    guard timeout.nanoseconds > 0, let deadline else {
        return isFirstPoll ? 0 : nil
    }

    let now = try monotonicNanoseconds()
    guard now < deadline else { return isFirstPoll ? 0 : nil }
    let remainingNanoseconds = deadline - now
    let milliseconds =
        remainingNanoseconds / 1_000_000
        + (remainingNanoseconds.isMultiple(of: 1_000_000) ? 0 : 1)
    return Int32(min(milliseconds, UInt64(Int32.max)))
}

private func monotonicNanoseconds() throws -> UInt64 {
    var time = timespec()
    guard clock_gettime(CLOCK_MONOTONIC, &time) == 0 else {
        throw TerminalEventSourceError.posix(
            operation: .readMonotonicClock,
            errorCode: errno
        )
    }

    let seconds = UInt64(time.tv_sec)
    let nanoseconds = UInt64(time.tv_nsec)
    let (secondNanoseconds, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
    return overflow ? UInt64.max : secondNanoseconds + nanoseconds
}

private func hasPollEvent(_ events: Int16, _ event: Int32) -> Bool {
    Int32(events) & event != 0
}

private func platformPipe(_ fileDescriptors: UnsafeMutablePointer<Int32>) -> Int32 {
    pipe(fileDescriptors)
}

private func platformPoll(
    _ fileDescriptors: UnsafeMutablePointer<pollfd>?,
    _ count: nfds_t,
    _ timeout: Int32
) -> Int32 {
    poll(fileDescriptors, count, timeout)
}

private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
) -> Int {
    #if canImport(Darwin)
        Darwin.read(fileDescriptor, buffer, count)
    #else
        Glibc.read(fileDescriptor, buffer, count)
    #endif
}

private func platformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
) -> Int {
    #if canImport(Darwin)
        Darwin.write(fileDescriptor, buffer, count)
    #else
        Glibc.write(fileDescriptor, buffer, count)
    #endif
}

private func platformClose(_ fileDescriptor: Int32) -> Int32 {
    #if canImport(Darwin)
        Darwin.close(fileDescriptor)
    #else
        Glibc.close(fileDescriptor)
    #endif
}

private func platformSigaction(
    _ signalNumber: Int32,
    _ action: UnsafePointer<sigaction>?,
    _ previousAction: UnsafeMutablePointer<sigaction>?
) -> Int32 {
    sigaction(signalNumber, action, previousAction)
}

private func platformYield() {
    #if canImport(Darwin)
        _ = Darwin.sched_yield()
    #else
        _ = Glibc.sched_yield()
    #endif
}
