import Testing

@testable import TermKit

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct TransportTests {
    @Test("Write retries EINTR and completes partial writes")
    func writeRetriesInterruptionsAndPartialWrites() throws {
        let script = TerminalPOSIXScript(writeSteps: [.interrupted, .count(2), .all])
        let transport = TerminalTransport(systemCalls: script.calls)

        try transport.writeAll(Array("hello".utf8))

        #expect(script.writtenText == "hello")
        #expect(script.writeCallCount == 3)
    }

    @Test("Read retries EINTR")
    func readRetriesInterruption() throws {
        let script = TerminalPOSIXScript(readSteps: [.interrupted, .bytes(Array("ok".utf8))])
        let transport = TerminalTransport(systemCalls: script.calls)

        #expect(try transport.read() == Array("ok".utf8))
        #expect(script.readCallCount == 2)
    }

    @Test("Permanent write error reports remaining bytes")
    func writeReportsRemainingBytes() {
        let script = TerminalPOSIXScript(writeSteps: [.count(2), .failure(EIO)])
        let transport = TerminalTransport(systemCalls: script.calls)

        #expect(
            throws: TerminalTransportError.posix(
                operation: .write,
                errorCode: EIO,
                remainingByteCount: 3
            )
        ) {
            try transport.writeAll(Array("hello".utf8))
        }
    }

    @Test("Zero-byte write is a typed stalled-write failure")
    func zeroByteWriteFails() {
        let script = TerminalPOSIXScript(writeSteps: [.zero])
        let transport = TerminalTransport(systemCalls: script.calls)

        #expect(throws: TerminalTransportError.stalledWrite(remainingByteCount: 1)) {
            try transport.writeAll([0x61])
        }
    }

    @Test("Synchronized frame is one buffered byte sequence")
    func synchronizedFrameIsBuffered() throws {
        let script = TerminalPOSIXScript()
        let transport = TerminalTransport(systemCalls: script.calls)

        try transport.beginFrame()
        try transport.appendToFrame(Array("frame".utf8))
        try transport.endFrame(synchronized: true)

        #expect(script.writeCallCount == 1)
        #expect(script.writtenText == "\u{1B}[?2026hframe\u{1B}[?2026l")
    }

    @Test("Frame buffer limit drops the active frame")
    func frameBufferIsBounded() throws {
        let transport = TerminalTransport(maximumFrameByteCount: 1_024, systemCalls: TerminalPOSIXScript().calls)
        try transport.beginFrame()

        #expect(throws: TerminalTransportError.frameTooLarge(limit: 1_024)) {
            try transport.appendToFrame(Array(repeating: 0x61, count: 1_025))
        }
        #expect(throws: TerminalTransportError.noActiveFrame) {
            try transport.endFrame(synchronized: false)
        }
    }

    @Test("Scoped frame cancels after thrown work")
    func scopedFrameCancelsAfterFailure() throws {
        enum TestError: Error { case expected }

        let script = TerminalPOSIXScript()
        let transport = TerminalTransport(systemCalls: script.calls)
        #expect(throws: TestError.expected) {
            try transport.withFrame(synchronized: false) {
                try transport.appendToFrame(Array("discarded".utf8))
                throw TestError.expected
            }
        }

        try transport.withFrame(synchronized: false) {
            try transport.appendToFrame(Array("written".utf8))
        }
        #expect(script.writtenText == "written")
    }
}
