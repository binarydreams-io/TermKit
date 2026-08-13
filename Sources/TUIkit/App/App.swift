//  🖥️ TUIKit — Terminal UI Kit for Swift
//  App.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - App Protocol

/// The base protocol for TUIkit applications.
///
/// `App` is the entry point for every TUIkit application,
/// similar to `App` in SwiftUI.
///
/// # Example
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///     }
/// }
/// ```
@MainActor
public protocol App {
  /// The type of the main scene.
  associatedtype Body: Scene

  /// The main scene of the app.
  @SceneBuilder
  var body: Body { get }

  /// Initializes the app.
  init()
}

extension App {
  /// Starts the app.
  ///
  /// This method is called by the `@main` attribute and starts
  /// the main run loop of the application.
  ///
  public static func main() {
    _ = Task { @MainActor in
      do {
        let runner = AppRunner<Self>(app: Self())
        try await runner.run()
        exit(EXIT_SUCCESS)
      } catch {
        writeApplicationFailure(error)
        exit(EXIT_FAILURE)
      }
    }
    dispatchMain()
  }
}

/// Writes a best-effort runtime failure diagnostic to standard error.
private func writeApplicationFailure(_ error: any Error) {
  let bytes = Array("TUIkit application failed: \(error)\n".utf8)
  let systemCalls = TerminalSystemCalls.system

  bytes.withUnsafeBufferPointer { buffer in
    guard let baseAddress = buffer.baseAddress else { return }
    var written = 0

    while written < buffer.count {
      let result = systemCalls.write(
        STDERR_FILENO,
        baseAddress + written,
        buffer.count - written
      )
      if result > 0 {
        written += result
      } else if result < 0, systemCalls.errorCode() == EINTR {
        continue
      } else {
        return
      }
    }
  }
}
