//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LocalizationKeys+Convenience.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Convenient Localization Extensions

extension LocalizedString {
  /// Creates a localized string view from a typed localization key.
  ///
  /// # Example
  ///
  /// ```swift
  /// LocalizedString(LocalizationKey.Button.ok)
  /// LocalizedString(LocalizationKey.Error.notFound)
  /// ```
  public init(_ key: LocalizationKey.Button) {
    self.init(key.rawValue)
  }

  /// Creates a localized string view from a label key.
  public init(_ key: LocalizationKey.Label) {
    self.init(key.rawValue)
  }

  /// Creates a localized string view from an error key.
  public init(_ key: LocalizationKey.Error) {
    self.init(key.rawValue)
  }

  /// Creates a localized string view from a placeholder key.
  public init(_ key: LocalizationKey.Placeholder) {
    self.init(key.rawValue)
  }

  /// Creates a localized string view from a menu key.
  public init(_ key: LocalizationKey.Menu) {
    self.init(key.rawValue)
  }

  /// Creates a localized string view from a dialog key.
  public init(_ key: LocalizationKey.Dialog) {
    self.init(key.rawValue)
  }

  /// Creates a localized string view from a validation key.
  public init(_ key: LocalizationKey.Validation) {
    self.init(key.rawValue)
  }
}

extension Text {
  /// Creates a text view with a localized string using a typed localization key.
  ///
  /// # Example
  ///
  /// ```swift
  /// Text(localized: LocalizationKey.Button.ok)
  /// Text(localized: LocalizationKey.Error.notFound)
  /// ```
  public init(localized key: LocalizationKey.Button) {
    self.init(localized: key.rawValue)
  }

  /// Creates a text view with a localized string from a label key.
  public init(localized key: LocalizationKey.Label) {
    self.init(localized: key.rawValue)
  }

  /// Creates a text view with a localized string from an error key.
  public init(localized key: LocalizationKey.Error) {
    self.init(localized: key.rawValue)
  }

  /// Creates a text view with a localized string from a placeholder key.
  public init(localized key: LocalizationKey.Placeholder) {
    self.init(localized: key.rawValue)
  }

  /// Creates a text view with a localized string from a menu key.
  public init(localized key: LocalizationKey.Menu) {
    self.init(localized: key.rawValue)
  }

  /// Creates a text view with a localized string from a dialog key.
  public init(localized key: LocalizationKey.Dialog) {
    self.init(localized: key.rawValue)
  }

  /// Creates a text view with a localized string from a validation key.
  public init(localized key: LocalizationKey.Validation) {
    self.init(localized: key.rawValue)
  }
}

extension LocalizationService {
  /// Retrieves a localized string for a typed key.
  ///
  /// # Example
  ///
  /// ```swift
  /// @Environment(\.localizationService) var localization
  /// let okText = localization.string(for: LocalizationKey.Button.ok)
  /// let errorText = localization.string(for: LocalizationKey.Error.notFound)
  /// ```
  public func string(for key: LocalizationKey.Button) -> String {
    string(for: key.rawValue)
  }

  /// Retrieves a localized string for a label key.
  public func string(for key: LocalizationKey.Label) -> String {
    string(for: key.rawValue)
  }

  /// Retrieves a localized string for an error key.
  public func string(for key: LocalizationKey.Error) -> String {
    string(for: key.rawValue)
  }

  /// Retrieves a localized string for a placeholder key.
  public func string(for key: LocalizationKey.Placeholder) -> String {
    string(for: key.rawValue)
  }

  /// Retrieves a localized string for a menu key.
  public func string(for key: LocalizationKey.Menu) -> String {
    string(for: key.rawValue)
  }

  /// Retrieves a localized string for a dialog key.
  public func string(for key: LocalizationKey.Dialog) -> String {
    string(for: key.rawValue)
  }

  /// Retrieves a localized string for a validation key.
  public func string(for key: LocalizationKey.Validation) -> String {
    string(for: key.rawValue)
  }
}
