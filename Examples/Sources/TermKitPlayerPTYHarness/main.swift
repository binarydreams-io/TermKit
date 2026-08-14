#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

guard CommandLine.arguments.count == 5,
    let inheritedMaster = Int32(CommandLine.arguments[3]),
    let inheritedSlave = Int32(CommandLine.arguments[4])
else { exit(64) }
_ = close(inheritedMaster)
_ = close(inheritedSlave)
guard setsid() >= 0 else { exit(71) }

let terminal = CommandLine.arguments[1].withCString { open($0, O_RDWR) }
guard terminal >= 0 else { exit(71) }
#if canImport(Darwin)
    guard Darwin.ioctl(terminal, TIOCSCTTY, 0) == 0 else { exit(71) }
#else
    guard Glibc.ioctl(terminal, UInt(TIOCSCTTY), 0) == 0 else { exit(71) }
#endif
guard tcsetpgrp(terminal, getpid()) == 0 else { exit(71) }
guard dup2(terminal, STDIN_FILENO) >= 0,
    dup2(terminal, STDOUT_FILENO) >= 0,
    dup2(terminal, STDERR_FILENO) >= 0
else { exit(71) }
if terminal > STDERR_FILENO { _ = close(terminal) }

var arguments = [strdup(CommandLine.arguments[2]), nil]
_ = arguments.withUnsafeMutableBufferPointer { buffer in
    execv(buffer[0]!, buffer.baseAddress!)
}
exit(71)
