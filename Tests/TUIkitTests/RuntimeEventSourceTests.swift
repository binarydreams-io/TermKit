//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RuntimeEventSourceTests.swift
//
//  License: MIT

import Testing

@testable import TUIkit

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

@MainActor
@Suite("Runtime Event Source Tests", .serialized)
struct RuntimeEventSourceTests {
    @Test("Runtime channel coalesces unread input readiness")
    func runtimeChannelCoalescesInputReadiness() async throws {
        let channel = RuntimeEventChannel()
        channel.send(.inputAvailable)
        channel.send(.inputAvailable)
        channel.send(.inputAvailable)

        var iterator = channel.events.makeAsyncIterator()
        let nextEvent = await iterator.next()
        let firstEvent = try #require(nextEvent)
        channel.didConsume(firstEvent)
        channel.send(.inputAvailable)
        channel.send(.shutdownRequested)
        let secondEvent = await iterator.next()
        if let secondEvent {
            channel.didConsume(secondEvent)
        }
        let thirdEvent = await iterator.next()
        channel.finish()

        if case .inputAvailable = firstEvent {
            // Expected event.
        } else {
            Issue.record("Expected an input readiness event")
        }
        if case .inputAvailable = secondEvent {
            // Expected event.
        } else {
            Issue.record("Expected input readiness after consuming the first event")
        }
        if case .shutdownRequested = thirdEvent {
            // Expected event.
        } else {
            Issue.record("Expected duplicate input readiness to be coalesced")
        }
    }

    @Test("Runtime channel coalesces unread render requests")
    func runtimeChannelCoalescesRenderRequests() async throws {
        let channel = RuntimeEventChannel()
        channel.send(.renderRequested)
        channel.send(.renderRequested)
        channel.send(.renderRequested)
        channel.send(.shutdownRequested)

        var iterator = channel.events.makeAsyncIterator()
        let nextFirstEvent = await iterator.next()
        let firstEvent = try #require(nextFirstEvent)
        channel.didConsume(firstEvent)
        channel.send(.renderRequested)
        channel.finish()

        let nextSecondEvent = await iterator.next()
        let secondEvent = try #require(nextSecondEvent)
        let nextThirdEvent = await iterator.next()
        let thirdEvent = try #require(nextThirdEvent)
        let fourthEvent = await iterator.next()

        if case .renderRequested = firstEvent {
            // Expected event.
        } else {
            Issue.record("Expected the first render request")
        }
        if case .shutdownRequested = secondEvent {
            // Expected event.
        } else {
            Issue.record("Expected shutdown to retain FIFO order")
        }
        if case .renderRequested = thirdEvent {
            // Expected event.
        } else {
            Issue.record("Expected a new render request after consuming the first")
        }
        #expect(fourthEvent == nil, "Expected duplicate render requests to be coalesced")
    }

    @Test("Signal sources deliver resize and termination events", .timeLimit(.minutes(1)))
    func signalSourcesDeliverRuntimeEvents() async throws {
        let channel = RuntimeEventChannel()
        let manager = SignalManager()
        await manager.install(sendingTo: channel)
        defer {
            manager.stop()
            channel.finish()
        }

        var iterator = channel.events.makeAsyncIterator()

        try #require(kill(getpid(), SIGWINCH) == 0)
        let resizeEvent = await iterator.next()
        if case .terminalResized = resizeEvent {
            // Expected event.
        } else {
            Issue.record("Expected a terminal resize event")
        }

        try #require(kill(getpid(), SIGTERM) == 0)
        let shutdownEvent = await iterator.next()
        if case .shutdownRequested = shutdownEvent {
            // Expected event.
        } else {
            Issue.record("Expected a shutdown event")
        }
    }

    @Test("Input source wakes only when its descriptor becomes readable", .timeLimit(.minutes(1)))
    func inputSourceDeliversReadiness() async throws {
        var descriptors: [Int32] = [0, 0]
        try #require(pipe(&descriptors) == 0)
        defer {
            close(descriptors[0])
            close(descriptors[1])
        }

        let channel = RuntimeEventChannel()
        let source = TerminalInputSource(fileDescriptor: descriptors[0])
        source.start(sendingTo: channel)
        defer {
            source.stop()
            channel.finish()
        }

        var byte: UInt8 = 0x41
        try #require(write(descriptors[1], &byte, 1) == 1)

        var iterator = channel.events.makeAsyncIterator()
        let event = await iterator.next()
        var readByte: UInt8 = 0
        try #require(read(descriptors[0], &readByte, 1) == 1)
        #expect(readByte == byte)
        if case .inputAvailable = event {
            // Expected event.
        } else {
            Issue.record("Expected an input readiness event")
        }
    }
}
