#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A bounded snapshot of environment values used for terminal detection.
public struct TerminalEnvironment: Equatable, Sendable {
    private static let recognizedNames = [
        "COLORTERM",
        "GHOSTTY_RESOURCES_DIR",
        "KITTY_WINDOW_ID",
        "TERM",
        "TERM_PROGRAM",
        "TMUX",
        "WT_SESSION",
    ]

    private let values: [String: String]

    /// Creates a snapshot from recognized environment values.
    ///
    /// Values larger than the byte limit are ignored. Unrecognized names are also ignored.
    public init(values: [String: String], maximumValueByteCount: Int = 4_096) {
        let limit = max(1, min(maximumValueByteCount, 65_536))
        var bounded: [String: String] = [:]
        bounded.reserveCapacity(Self.recognizedNames.count)
        for name in Self.recognizedNames {
            guard let value = values[name], value.utf8.count <= limit else { continue }
            bounded[name] = value
        }
        self.values = bounded
    }

    /// Reads a bounded snapshot from the process environment.
    public static func current(maximumValueByteCount: Int = 4_096) -> Self {
        let limit = max(1, min(maximumValueByteCount, 65_536))
        var values: [String: String] = [:]
        values.reserveCapacity(recognizedNames.count)

        for name in recognizedNames {
            guard let pointer = getenv(name) else { continue }
            var byteCount = 0
            while byteCount <= limit, pointer[byteCount] != 0 {
                byteCount += 1
            }
            guard byteCount <= limit else { continue }
            let bytes = UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self)
            values[name] = String(decoding: UnsafeBufferPointer(start: bytes, count: byteCount), as: UTF8.self)
        }
        return Self(values: values, maximumValueByteCount: limit)
    }

    /// Returns the captured value for a recognized name.
    public subscript(name: String) -> String? {
        values[name]
    }
}

/// Supplies a terminfo capability record without invoking a command.
public protocol TerminfoHintProvider: Sendable {
    /// Returns a terminfo source record for the specified terminal name.
    func capabilityRecord(for terminalName: String) -> [UInt8]?
}

/// Supplies one caller-provided terminfo capability record.
public struct StaticTerminfoHintProvider: TerminfoHintProvider, Sendable {
    private let record: [UInt8]

    /// Creates a provider from caller-supplied bytes.
    public init(record: [UInt8]) {
        self.record = record
    }

    public func capabilityRecord(for terminalName: String) -> [UInt8]? {
        record
    }
}

/// Reads a bounded terminfo source record from `infocmp`.
public struct InfocmpTerminfoHintProvider: TerminfoHintProvider, Sendable {
    /// The default maximum execution time.
    public static let defaultTimeoutMilliseconds: Int32 = 100

    private let executablePath: String
    private let maximumRecordByteCount: Int
    private let timeoutMilliseconds: Int32

    /// Creates a provider with bounded output and execution time.
    public init(
        executablePath: String = "/usr/bin/infocmp",
        maximumRecordByteCount: Int = 16_384,
        timeoutMilliseconds: Int32 = defaultTimeoutMilliseconds
    ) {
        self.executablePath = executablePath
        self.maximumRecordByteCount = min(max(maximumRecordByteCount, 64), 65_536)
        self.timeoutMilliseconds = min(max(timeoutMilliseconds, 10), 1_000)
    }

    public func capabilityRecord(for terminalName: String) -> [UInt8]? {
        guard !terminalName.isEmpty, terminalName.utf8.count <= 256,
              terminalName.utf8.allSatisfy({ byte in
                  (0x30 ... 0x39).contains(byte) || (0x41 ... 0x5A).contains(byte)
                      || (0x61 ... 0x7A).contains(byte) || byte == 0x2B || byte == 0x2D
                      || byte == 0x2E || byte == 0x5F
              }) else { return nil }

        var descriptors = [Int32](repeating: -1, count: 2)
        guard pipe(&descriptors) == 0 else { return nil }
        defer {
            if descriptors[0] >= 0 { _ = close(descriptors[0]) }
            if descriptors[1] >= 0 { _ = close(descriptors[1]) }
        }

        #if os(Linux)
        var actions = posix_spawn_file_actions_t()
        #else
        var actions: posix_spawn_file_actions_t?
        #endif
        guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO) == 0,
              posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0,
              posix_spawn_file_actions_addclose(&actions, descriptors[0]) == 0,
              posix_spawn_file_actions_addclose(&actions, descriptors[1]) == 0 else { return nil }

        var processID = pid_t()
        let spawnStatus = withCStringArguments([executablePath, "-1", terminalName]) { arguments in
            executablePath.withCString { path in
                posix_spawn(&processID, path, &actions, nil, arguments, environ)
            }
        }
        guard spawnStatus == 0 else { return nil }
        _ = close(descriptors[1])
        descriptors[1] = -1

        let flags = fcntl(descriptors[0], F_GETFL)
        guard flags >= 0, fcntl(descriptors[0], F_SETFL, flags | O_NONBLOCK) == 0 else {
            terminateAndWait(processID)
            return nil
        }

        var output: [UInt8] = []
        output.reserveCapacity(min(maximumRecordByteCount, 4_096))
        var pollDescriptor = pollfd(fd: descriptors[0], events: Int16(POLLIN | POLLHUP), revents: 0)
        let deadline = monotonicMilliseconds() + UInt64(timeoutMilliseconds)
        while monotonicMilliseconds() < deadline {
            let remaining = Int32(min(UInt64(Int32.max), deadline - monotonicMilliseconds()))
            let pollResult = poll(&pollDescriptor, 1, remaining)
            if pollResult < 0, errno == EINTR { continue }
            guard pollResult >= 0 else { break }
            if pollResult == 0 { continue }

            var buffer = [UInt8](repeating: 0, count: min(4_096, maximumRecordByteCount + 1 - output.count))
            let count = buffer.withUnsafeMutableBytes { read(descriptors[0], $0.baseAddress, $0.count) }
            if count > 0 {
                output.append(contentsOf: buffer.prefix(count))
                if output.count > maximumRecordByteCount {
                    terminateAndWait(processID)
                    return nil
                }
                continue
            }
            if count < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
            if count == 0 {
                var status = Int32()
                guard waitpid(processID, &status, 0) == processID, processExitedSuccessfully(status) else { return nil }
                return output
            }
            break
        }
        terminateAndWait(processID)
        return nil
    }
}

/// Resource limits for terminfo hint parsing.
public struct TerminfoHintPolicy: Equatable, Sendable {
    /// The maximum record size in bytes.
    public let maximumRecordByteCount: Int

    /// The maximum number of comma-separated fields.
    public let maximumFieldCount: Int

    /// The maximum field size in bytes.
    public let maximumFieldByteCount: Int

    /// Creates bounded parser limits.
    public init(
        maximumRecordByteCount: Int = 16_384,
        maximumFieldCount: Int = 256,
        maximumFieldByteCount: Int = 1_024
    ) {
        self.maximumRecordByteCount = min(max(maximumRecordByteCount, 64), 65_536)
        self.maximumFieldCount = min(max(maximumFieldCount, 8), 1_024)
        self.maximumFieldByteCount = min(max(maximumFieldByteCount, 8), 4_096)
    }
}

/// A failure that caused terminfo hints to be discarded.
public enum TerminfoHintDiagnostic: Equatable, Sendable {
    /// The record exceeded the configured byte limit.
    case recordTooLarge(limit: Int)

    /// The record exceeded the configured field limit.
    case tooManyFields(limit: Int)

    /// A field exceeded the configured byte limit.
    case fieldTooLarge(index: Int, limit: Int)

    /// The record contained a byte outside the supported ASCII range.
    case invalidByte(index: Int)

    /// A recognized field contained an invalid value.
    case malformedField(index: Int)
}

/// Safe capability hints parsed from a terminfo source record.
public struct TerminfoHints: Equatable, Sendable {
    /// A color capability, when the record specifies one.
    public var color: TerminalColorCapability?

    /// Whether the record identifies bracketed-paste support.
    public var supportsBracketedPaste: Bool

    /// Whether the record identifies SGR mouse support.
    public var supportsSGRMouse: Bool

    /// Whether the record identifies focus-reporting support.
    public var supportsFocusReporting: Bool

    /// Whether the record identifies Kitty keyboard support.
    public var supportsKittyKeyboard: Bool

    public init(
        color: TerminalColorCapability? = nil,
        supportsBracketedPaste: Bool = false,
        supportsSGRMouse: Bool = false,
        supportsFocusReporting: Bool = false,
        supportsKittyKeyboard: Bool = false
    ) {
        self.color = color
        self.supportsBracketedPaste = supportsBracketedPaste
        self.supportsSGRMouse = supportsSGRMouse
        self.supportsFocusReporting = supportsFocusReporting
        self.supportsKittyKeyboard = supportsKittyKeyboard
    }
}

/// The result of parsing a bounded terminfo hint record.
public struct TerminfoHintParseResult: Equatable, Sendable {
    /// Parsed hints. This value is empty when `diagnostic` is not `nil`.
    public let hints: TerminfoHints

    /// The parse failure, when the parser discarded the record.
    public let diagnostic: TerminfoHintDiagnostic?
}

/// Parses a bounded, caller-supplied terminfo source record.
public struct TerminfoHintParser: Sendable {
    private let policy: TerminfoHintPolicy

    /// Creates a parser with bounded resource limits.
    public init(policy: TerminfoHintPolicy = TerminfoHintPolicy()) {
        self.policy = policy
    }

    /// Parses capability names without reading files or invoking commands.
    public func parse(_ record: [UInt8]) -> TerminfoHintParseResult {
        guard record.count <= policy.maximumRecordByteCount else {
            return failure(.recordTooLarge(limit: policy.maximumRecordByteCount))
        }
        if let index = record.firstIndex(where: { $0 != 0x09 && $0 != 0x0A && $0 != 0x0D && !(0x20 ... 0x7E).contains($0) }) {
            return failure(.invalidByte(index: index))
        }

        let fields = record.split(separator: 0x2C, omittingEmptySubsequences: false)
        guard fields.count <= policy.maximumFieldCount else {
            return failure(.tooManyFields(limit: policy.maximumFieldCount))
        }

        var hints = TerminfoHints()
        for (index, rawField) in fields.enumerated() {
            let field = rawField.drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D })
                .reversed().drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }).reversed()
            guard field.count <= policy.maximumFieldByteCount else {
                return failure(.fieldTooLarge(index: index, limit: policy.maximumFieldByteCount))
            }
            guard !field.isEmpty else { continue }

            let value = String(decoding: field, as: UTF8.self).lowercased()
            if value.hasPrefix("colors#") {
                guard let count = Int(value.dropFirst("colors#".count)), count >= 0 else {
                    return failure(.malformedField(index: index))
                }
                hints.color = count >= 16_777_216 ? .trueColor : count >= 256 ? .ansi256 : count >= 8 ? .ansi16 : .monochrome
            } else if value == "rgb" || value == "tc" || value.hasPrefix("setrgbf=") || value.hasPrefix("setrgbb=") {
                hints.color = .trueColor
            } else if value == "be" || value == "brpaste" || value == "bracketed_paste" {
                hints.supportsBracketedPaste = true
            } else if value == "xm" || value == "kmous" || value.hasPrefix("kmous=") {
                hints.supportsSGRMouse = true
            } else if value == "focus" || value == "focus_reporting" {
                hints.supportsFocusReporting = true
            } else if value == "kitty_keyboard" {
                hints.supportsKittyKeyboard = true
            }
        }
        return TerminfoHintParseResult(hints: hints, diagnostic: nil)
    }

    private func failure(_ diagnostic: TerminfoHintDiagnostic) -> TerminfoHintParseResult {
        TerminfoHintParseResult(hints: TerminfoHints(), diagnostic: diagnostic)
    }
}

/// Capabilities and any diagnostic from optional terminfo hints.
public struct TerminalCapabilityDetection: Equatable, Sendable {
    /// The detected terminal capabilities.
    public let capabilities: TerminalCapabilities

    /// The terminfo parse failure, when the detector discarded the record.
    public let terminfoDiagnostic: TerminfoHintDiagnostic?
}

/// Detects safe capability hints without terminal I/O.
public enum TerminalCapabilityDetector {
    /// Returns capabilities inferred from bounded environment hints.
    ///
    /// Synchronized output stays unknown because the protocol has a query.
    public static func capabilities(
        from environment: TerminalEnvironment,
        terminfoHintProvider: (any TerminfoHintProvider)? = nil,
        terminfoHintPolicy: TerminfoHintPolicy = TerminfoHintPolicy(),
        allowsOSC52: Bool = false
    ) -> TerminalCapabilities {
        detection(
            from: environment,
            terminfoHintProvider: terminfoHintProvider,
            terminfoHintPolicy: terminfoHintPolicy,
            allowsOSC52: allowsOSC52
        ).capabilities
    }

    /// Returns capabilities and a typed diagnostic for invalid terminfo hints.
    public static func detection(
        from environment: TerminalEnvironment,
        terminfoHintProvider: (any TerminfoHintProvider)? = nil,
        terminfoHintPolicy: TerminfoHintPolicy = TerminfoHintPolicy(),
        allowsOSC52: Bool = false
    ) -> TerminalCapabilityDetection {
        let term = environment["TERM"]?.lowercased() ?? ""
        let colorTerm = environment["COLORTERM"]?.lowercased() ?? ""
        let isDumb = term == "dumb"

        let color: TerminalColorCapability
        if isDumb {
            color = .monochrome
        } else if colorTerm == "truecolor" || colorTerm == "24bit" {
            color = .trueColor
        } else if term.contains("256color") {
            color = .ansi256
        } else {
            color = .ansi16
        }

        let parsed = terminfoHintProvider?.capabilityRecord(for: term).map {
            TerminfoHintParser(policy: terminfoHintPolicy).parse($0)
        }
        let hints = parsed?.hints ?? TerminfoHints()
        let isKitty = environment["KITTY_WINDOW_ID"] != nil || term.contains("kitty")
        let capabilities = TerminalCapabilities(
            color: max(color, hints.color ?? color),
            synchronizedOutput: .unknown,
            supportsBracketedPaste: isDumb == false || hints.supportsBracketedPaste,
            supportsSGRMouse: isDumb == false || hints.supportsSGRMouse,
            supportsFocusReporting: isDumb == false || hints.supportsFocusReporting,
            supportsKittyKeyboard: isKitty || hints.supportsKittyKeyboard,
            allowsOSC52: allowsOSC52
        )
        return TerminalCapabilityDetection(
            capabilities: capabilities,
            terminfoDiagnostic: parsed?.diagnostic
        )
    }
}

/// Limits a synchronized-output query.
public struct TerminalProbePolicy: Equatable, Sendable {
    /// Whether a failed timeout can use capability fallback.
    public enum TimeoutRequirement: Equatable, Sendable {
        /// A timeout selects the safe fallback.
        case optional

        /// A timeout throws a typed error.
        case mandatory
    }

    /// The minimum accepted timeout.
    public static let minimumTimeout: Duration = .milliseconds(10)

    /// The maximum accepted timeout.
    public static let maximumTimeout: Duration = .seconds(1)

    /// The query timeout.
    public let timeout: Duration

    /// The maximum number of response bytes.
    public let maximumResponseByteCount: Int

    /// The behavior when the terminal does not respond before the deadline.
    public let timeoutRequirement: TimeoutRequirement

    /// Creates a bounded query policy.
    ///
    /// The initializer clamps the timeout to 10 milliseconds through 1 second.
    /// It clamps the response limit to 32 through 4,096 bytes.
    public init(
        timeout: Duration = .milliseconds(150),
        maximumResponseByteCount: Int = 256,
        timeoutRequirement: TimeoutRequirement = .optional
    ) {
        self.timeout = min(max(timeout, Self.minimumTimeout), Self.maximumTimeout)
        self.maximumResponseByteCount = min(max(maximumResponseByteCount, 32), 4_096)
        self.timeoutRequirement = timeoutRequirement
    }
}

/// A mandatory capability probe failure.
public enum TerminalCapabilityProbeError: Error, Equatable, Sendable {
    /// The synchronized-output query did not complete before the deadline.
    case synchronizedOutputTimedOut(timeout: Duration)
}

/// A synchronized-output query result.
public enum SynchronizedOutputProbeResult: Equatable, Sendable {
    /// The terminal recognizes and permits synchronized output.
    case supported

    /// The terminal does not recognize or cannot enable synchronized output.
    case unsupported

    /// The terminal did not respond before the deadline.
    case timedOut

    /// The response exceeded the configured byte limit.
    case responseTooLarge(limit: Int)
}

/// Parses a DEC mode report for synchronized output.
public struct SynchronizedOutputQueryParser: Sendable {
    private let maximumResponseByteCount: Int
    private var bytes: [UInt8] = []
    private var result: SynchronizedOutputProbeResult?

    /// Creates a bounded response parser.
    public init(maximumResponseByteCount: Int = 256) {
        self.maximumResponseByteCount = min(max(maximumResponseByteCount, 32), 4_096)
        bytes.reserveCapacity(min(self.maximumResponseByteCount, 256))
    }

    /// Adds response bytes and returns a result when one is available.
    public mutating func append(_ newBytes: [UInt8]) -> SynchronizedOutputProbeResult? {
        guard result == nil else { return result }
        guard bytes.count <= maximumResponseByteCount - min(newBytes.count, maximumResponseByteCount) else {
            result = .responseTooLarge(limit: maximumResponseByteCount)
            bytes.removeAll(keepingCapacity: false)
            return result
        }
        bytes.append(contentsOf: newBytes)
        if bytes.count > maximumResponseByteCount {
            result = .responseTooLarge(limit: maximumResponseByteCount)
            bytes.removeAll(keepingCapacity: false)
            return result
        }
        result = parseModeReport()
        return result
    }

    private func parseModeReport() -> SynchronizedOutputProbeResult? {
        let prefix = Array("\u{1B}[?2026;".utf8)
        let suffix = Array("$y".utf8)
        guard bytes.count >= prefix.count + suffix.count + 1 else { return nil }

        for start in bytes.indices where bytes[start...].starts(with: prefix) {
            let valueStart = start + prefix.count
            guard valueStart < bytes.count else { return nil }
            var valueEnd = valueStart
            while valueEnd < bytes.count, bytes[valueEnd].isASCIIDigit {
                valueEnd += 1
            }
            guard valueEnd > valueStart else { continue }
            guard valueEnd + suffix.count <= bytes.count else { return nil }
            guard bytes[valueEnd ..< (valueEnd + suffix.count)].elementsEqual(suffix) else { continue }
            guard let value = Int(String(decoding: bytes[valueStart ..< valueEnd], as: UTF8.self)) else { continue }
            return value == 1 || value == 2 || value == 3 ? .supported : .unsupported
        }
        return nil
    }
}

/// A nonblocking synchronized-output probe state machine.
public struct SynchronizedOutputProbe: Sendable {
    /// The DEC private-mode query for mode 2026.
    public static let query = Array("\u{1B}[?2026$p".utf8)

    private enum State: Sendable {
        case idle
        case waiting
        case complete(SynchronizedOutputProbeResult)
    }

    private let policy: TerminalProbePolicy
    private var parser: SynchronizedOutputQueryParser
    private var state: State = .idle

    /// Creates a probe without reading from the terminal.
    public init(policy: TerminalProbePolicy = TerminalProbePolicy()) {
        self.policy = policy
        self.parser = SynchronizedOutputQueryParser(maximumResponseByteCount: policy.maximumResponseByteCount)
    }

    /// Starts the probe and returns the bytes that the caller must write.
    ///
    /// The caller must monitor terminal input and enforce ``TerminalProbePolicy/timeout``.
    public mutating func start() -> [UInt8] {
        guard case .idle = state else { return [] }
        state = .waiting
        return Self.query
    }

    /// Adds bytes received while the query is active.
    public mutating func receive(_ bytes: [UInt8]) -> SynchronizedOutputProbeResult? {
        guard case .waiting = state else { return completedResult }
        guard let result = parser.append(bytes) else { return nil }
        state = .complete(result)
        return result
    }

    /// Completes the probe when the elapsed time reaches the policy timeout.
    public mutating func checkTimeout(elapsed: Duration) -> SynchronizedOutputProbeResult? {
        guard case .waiting = state else { return completedResult }
        guard elapsed >= policy.timeout else { return nil }
        state = .complete(.timedOut)
        return .timedOut
    }

    /// Applies a definitive probe result to terminal capabilities.
    public static func applying(
        _ result: SynchronizedOutputProbeResult,
        to capabilities: TerminalCapabilities
    ) -> TerminalCapabilities {
        var updated = capabilities
        switch result {
        case .supported:
            updated.synchronizedOutput = .supported
        case .unsupported, .timedOut, .responseTooLarge:
            updated.synchronizedOutput = .unsupported
        }
        return updated
    }

    private var completedResult: SynchronizedOutputProbeResult? {
        guard case let .complete(result) = state else { return nil }
        return result
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool {
        (0x30 ... 0x39).contains(self)
    }
}

private func withCStringArguments<Result>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
) -> Result {
    let storage = strings.map { strdup($0) }
    defer { storage.forEach { free($0) } }
    var arguments = storage + [nil]
    return arguments.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
}

private func monotonicMilliseconds() -> UInt64 {
    var time = timespec()
    clock_gettime(CLOCK_MONOTONIC, &time)
    return UInt64(time.tv_sec) * 1_000 + UInt64(time.tv_nsec) / 1_000_000
}

private func terminateAndWait(_ processID: pid_t) {
    _ = kill(processID, SIGKILL)
    while waitpid(processID, nil, 0) < 0, errno == EINTR {}
}

private func processExitedSuccessfully(_ status: Int32) -> Bool {
    return status & 0x7f == 0 && (status >> 8) & 0xff == 0
}
