/// A zero-based terminal cell position.
public struct TerminalCellPoint: Equatable, Hashable, Sendable {
  /// The zero-based column.
  public var column: Int

  /// The zero-based row.
  public var row: Int

  /// Creates a terminal cell position.
  public init(column: Int, row: Int) {
    self.column = column
    self.row = row
  }
}

/// A terminal size in cells.
public struct TerminalSize: Equatable, Hashable, Sendable {
  /// The number of columns.
  public var columns: Int

  /// The number of rows.
  public var rows: Int

  /// Creates a terminal size.
  public init(columns: Int, rows: Int) {
    self.columns = columns
    self.rows = rows
  }
}

/// The color precision that a terminal can display.
public enum TerminalColorCapability: Int, Comparable, Sendable {
  /// The terminal has no known color support.
  case monochrome

  /// The terminal supports the basic ANSI palette.
  case ansi16

  /// The terminal supports the 256-color ANSI palette.
  case ansi256

  /// The terminal supports 24-bit RGB colors.
  case trueColor

  /// Returns whether the left capability has less color precision.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// The detection state of an optional terminal capability.
public enum TerminalCapabilitySupport: Equatable, Sendable {
  /// Detection did not produce a definitive result.
  case unknown

  /// Detection showed that the terminal does not support the capability.
  case unsupported

  /// Detection showed that the terminal supports the capability.
  case supported
}

/// The terminal capabilities used by input and presentation code.
public struct TerminalCapabilities: Equatable, Sendable {
  /// The terminal color precision.
  public var color: TerminalColorCapability

  /// The synchronized-output detection state.
  public var synchronizedOutput: TerminalCapabilitySupport

  /// Whether bracketed paste can be enabled.
  public var supportsBracketedPaste: Bool

  /// Whether SGR mouse reporting can be enabled.
  public var supportsSGRMouse: Bool

  /// Whether focus reporting can be enabled.
  public var supportsFocusReporting: Bool

  /// Whether Kitty keyboard enhancements can be enabled.
  public var supportsKittyKeyboard: Bool

  /// Whether OSC 52 output is allowed by application policy.
  public var allowsOSC52: Bool

  /// Creates a set of terminal capabilities.
  public init(
    color: TerminalColorCapability = .ansi16,
    synchronizedOutput: TerminalCapabilitySupport = .unknown,
    supportsBracketedPaste: Bool = true,
    supportsSGRMouse: Bool = true,
    supportsFocusReporting: Bool = true,
    supportsKittyKeyboard: Bool = false,
    allowsOSC52: Bool = false
  ) {
    self.color = color
    self.synchronizedOutput = synchronizedOutput
    self.supportsBracketedPaste = supportsBracketedPaste
    self.supportsSGRMouse = supportsSGRMouse
    self.supportsFocusReporting = supportsFocusReporting
    self.supportsKittyKeyboard = supportsKittyKeyboard
    self.allowsOSC52 = allowsOSC52
  }
}
