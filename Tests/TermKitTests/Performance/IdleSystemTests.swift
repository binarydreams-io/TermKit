import Dispatch
import Testing

@testable import TermKit

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@Suite(
    "Section 15 idle system contract",
    .serialized,
    .disabled(
        if: termKitPerformanceTestsEnabled == false,
        "Set TERMKIT_RUN_PERFORMANCE_TESTS=1 and use a release build."
    )
)
struct IdleSystemTests {
    @Test("The real event source has no periodic idle wake", .timeLimit(.minutes(1)))
    func noPeriodicIdleWake() throws {
        var inputDescriptors: [Int32] = [-1, -1]
        var resultDescriptors: [Int32] = [-1, -1]
        try #require(pipe(&inputDescriptors) == 0)
        try #require(pipe(&resultDescriptors) == 0)
        let inputReadDescriptor = inputDescriptors[0]
        let inputWriteDescriptor = inputDescriptors[1]
        let resultReadDescriptor = resultDescriptors[0]
        let resultWriteDescriptor = resultDescriptors[1]
        defer {
            _ = close(inputReadDescriptor)
            _ = close(inputWriteDescriptor)
            _ = close(resultReadDescriptor)
            _ = close(resultWriteDescriptor)
        }

        let source = try TerminalEventSource(inputFileDescriptor: inputReadDescriptor)
        let finished = DispatchGroup()
        finished.enter()
        DispatchQueue.global().async {
            let outcome: UInt8
            do {
                outcome = try source.nextEvent(timeout: nil) == .wake ? 1 : 2
            } catch {
                outcome = 255
            }
            var byte = outcome
            _ = write(resultWriteDescriptor, &byte, 1)
            finished.leave()
        }

        var descriptor = pollfd(fd: resultReadDescriptor, events: Int16(POLLIN), revents: 0)
        #expect(poll(&descriptor, 1, 100) == 0)
        try source.wake()
        try #require(finished.wait(timeout: .now() + 1) == .success)

        var result: UInt8 = 0
        try #require(read(resultReadDescriptor, &result, 1) == 1)
        #expect(result == 1)
    }
}
