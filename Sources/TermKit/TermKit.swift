import Foundation

/// Provides information about the current TermKit release.
public enum TermKitRelease {
  /// The release version from the bundled version resource.
  public static let version: String = {
    guard let url = Bundle.module.url(forResource: "VERSION", withExtension: nil) else {
      preconditionFailure("TermKit VERSION resource is missing.")
    }
    do {
      return try String(contentsOf: url, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      preconditionFailure("TermKit VERSION resource could not be read: \(error)")
    }
  }()
}
