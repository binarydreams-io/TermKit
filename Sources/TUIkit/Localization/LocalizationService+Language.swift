//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LocalizationService+Language.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

extension LocalizationService {
  /// Supported languages
  public enum Language: String, Codable {
    case english = "en"
    case german = "de"
    case french = "fr"
    case italian = "it"
    case spanish = "es"

    /// Human-readable name
    public var displayName: String {
      switch self {
      case .english: "English"
      case .german: "Deutsch"
      case .french: "Français"
      case .italian: "Italiano"
      case .spanish: "Español"
      }
    }
  }

  /// Returns the system-preferred language if supported.
  static func systemPreferredLanguage() -> Language? {
    let preferredLanguages = NSLocale.preferredLanguages
    for langCode in preferredLanguages {
      let base = langCode.prefix(2).lowercased()
      if let language = Language(rawValue: base) {
        return language
      }
    }
    return nil
  }

  /// Loads stored language preference from the default config file.
  static func loadLanguagePreference() -> Language? {
    loadLanguagePreference(from: defaultConfigDirectoryPath())
  }

  /// Loads stored language preference from a specific config directory.
  static func loadLanguagePreference(from configDirectory: String) -> Language? {
    let path = (configDirectory as NSString).appendingPathComponent("language")
    guard FileManager.default.fileExists(atPath: path) else {
      return nil
    }

    do {
      let content = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      return Language(rawValue: content)
    } catch {
      return nil
    }
  }

  /// Returns the XDG-compatible default config directory path.
  static func defaultConfigDirectoryPath() -> String {
    #if os(macOS)
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first?.path ?? NSHomeDirectory()
    return (appSupport as NSString).appendingPathComponent("tuikit")
    #else
    let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
      ?? ((NSHomeDirectory() as NSString).appendingPathComponent(".config"))
    return (configHome as NSString).appendingPathComponent("tuikit")
    #endif
  }
}
